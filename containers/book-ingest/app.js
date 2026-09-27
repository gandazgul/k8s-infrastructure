import fs from 'node:fs/promises';
import { loadConfig } from './lib/config.js';
import { createLogger } from './lib/logger.js';
import { TransmissionClient } from './lib/transmission.js';
import { extractMetadata } from './lib/metadata.js';
import { classifyCandidateGroup, groupCandidates } from './lib/classify.js';
import {
    archiveTorrentFile,
    copyCandidate,
    ensureDirectories,
    listInboxFiles,
    planDestination,
    resolveCollision,
    scanTorrentFiles,
} from './lib/files.js';
import { loadImportState } from './lib/import-state.js';

const summary = {
    torrentsAdded: 0,
    torrentDuplicates: 0,
    completedTorrentsScanned: 0,
    filesCopied: 0,
    filesSkipped: 0,
    archivesIgnored: 0,
    errors: 0,
};

async function submitInboxTorrents(config, logger, transmission) {
    const torrentFiles = await listInboxFiles(config, logger);

    if (torrentFiles.length === 0) {
        logger.info('inbox', 'no torrent files pending');
    }

    for (const torrentFile of torrentFiles) {
        try {
            const metainfo = await fs.readFile(torrentFile, 'base64');
            const result = await transmission.addTorrent(metainfo);

            if (result.status === 'duplicate') {
                summary.torrentDuplicates += 1;
                logger.info('inbox', 'torrent already exists in Transmission; archiving inbox file', { torrentFile, torrent: result.torrent?.name });
            }
            else {
                summary.torrentsAdded += 1;
                logger.info('inbox', 'submitted torrent to Transmission', { torrentFile, torrent: result.torrent?.name, downloadDir: config.transmissionDownloadDir });
            }

            await archiveTorrentFile(torrentFile, config, logger);
        }
        catch (err) {
            summary.errors += 1;
            logger.error('inbox', 'failed to submit torrent file; leaving it for retry', { torrentFile, error: err.message });
        }
    }
}

async function importCompletedTorrents(config, logger, transmission, state) {
    const torrents = await transmission.getCompletedBookTorrents();
    summary.completedTorrentsScanned = torrents.length;

    if (torrents.length === 0) {
        logger.info('transmission', 'no completed book torrents found');

        return;
    }

    for (const torrent of torrents) {
        logger.info('transmission', 'scanning completed book torrent', { name: torrent.name, hashString: torrent.hashString, downloadDir: torrent.downloadDir });
        const candidates = await scanTorrentFiles(torrent, config, logger, summary);
        const groups = groupCandidates(candidates);

        for (const group of groups) {
            const metadataBySource = new Map();

            for (const candidate of group) {
                if (state.has(candidate)) {
                    summary.filesSkipped += 1;
                    logger.info('state', 'source file already imported with same size and mtime', { source: candidate.sourcePath });
                    continue;
                }

                const metadata = await extractMetadata(candidate.sourcePath, config, logger);
                metadataBySource.set(candidate.sourcePath, metadata);
            }

            const pendingGroup = group.filter((candidate) => !state.has(candidate));

            if (pendingGroup.length === 0) {
                continue;
            }

            const classification = classifyCandidateGroup(pendingGroup, metadataBySource);
            logger.info('classify', 'planned destination group', { torrent: torrent.name, confident: classification.confident, reason: classification.reason, author: classification.author, title: classification.title, reviewName: classification.reviewName });

            for (const candidate of pendingGroup) {
                try {
                    const plannedDestination = planDestination(candidate, classification, config);
                    const resolved = await resolveCollision(plannedDestination, candidate, logger);

                    if (resolved.action === 'already-present') {
                        state.add(candidate, resolved.destination);
                        summary.filesSkipped += 1;
                        logger.info('copy', 'destination already present with same size; recorded state', { source: candidate.sourcePath, destination: resolved.destination });
                        continue;
                    }

                    const copied = await copyCandidate(candidate, resolved.destination, config, logger);
                    state.add(candidate, resolved.destination);

                    if (copied) {
                        summary.filesCopied += 1;
                        logger.info('copy', 'copied source file', { source: candidate.sourcePath, destination: resolved.destination });
                    }
                }
                catch (err) {
                    summary.errors += 1;
                    logger.error('copy', 'failed to import source file', { source: candidate.sourcePath, error: err.message });
                }
            }
        }
    }
}

async function main() {
    const config = loadConfig();
    const logger = createLogger(config.logLevel);
    const transmission = new TransmissionClient(config, logger);

    logger.info('config', 'book ingest starting', {
        transmissionRpcUrl: config.transmissionRpcUrl,
        transmissionDownloadDir: config.transmissionDownloadDir,
        transmissionBooksPath: config.transmissionBooksPath,
        torrentInbox: config.torrentInbox,
        booksDest: config.booksDest,
        dryRun: config.dryRun,
    });

    await ensureDirectories(config);
    const state = await loadImportState(config, logger);

    await submitInboxTorrents(config, logger, transmission);
    await importCompletedTorrents(config, logger, transmission, state);

    if (!config.dryRun) {
        await state.saveAtomic();
    }

    logger.summary(summary);

    if (summary.errors > 0) {
        process.exit(1);
    }
}

main().catch((err) => {
    const logger = createLogger(process.env.LOG_LEVEL || 'info');
    summary.errors += 1;
    logger.error('fatal', 'book ingest failed', { error: err.stack || err.message });
    logger.summary(summary);
    process.exit(1);
});
