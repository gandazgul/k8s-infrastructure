import fs from 'node:fs/promises';
import path from 'node:path';

export function sanitizeSegment(segment, fallback = 'unknown') {
    const sanitized = String(segment || '')
        .replace(/[\\/\0-\x1F\x7F]/g, ' ')
        .replace(/[<>:"|?*]/g, ' ')
        .replace(/\.\.+/g, '.')
        .replace(/\s+/g, ' ')
        .trim()
        .replace(/^\.+$/, '');

    return sanitized || fallback;
}

export function hasArchiveExtension(filePath, ignoredArchiveExtensions) {
    const lower = filePath.toLowerCase();

    return [...ignoredArchiveExtensions].some((extension) => lower.endsWith(extension));
}

export function classifyPath(filePath, config) {
    const basename = path.basename(filePath);

    if (basename.startsWith('.') || basename.endsWith('.part') || basename.endsWith('.tmp')) {
        return { kind: 'temporary', reason: 'hidden or partial file' };
    }

    if (hasArchiveExtension(filePath, config.ignoredArchiveExtensions)) {
        return { kind: 'archive', reason: 'compressed archives are not extracted' };
    }

    const extension = path.extname(filePath).toLowerCase();

    if (config.supportedExtensions.has(extension)) {
        return { kind: 'supported', reason: 'supported extension' };
    }

    return { kind: 'unsupported', reason: `unsupported extension ${extension || '(none)'}` };
}

export async function ensureDirectories(config) {
    await fs.mkdir(config.torrentInbox, { recursive: true });
    await fs.mkdir(config.torrentArchive, { recursive: true });
    await fs.mkdir(config.stateDir, { recursive: true });
    await fs.mkdir(config.booksDest, { recursive: true });
    await fs.mkdir(config.needsReviewDir, { recursive: true });
}

export async function listInboxFiles(config, logger) {
    const entries = await fs.readdir(config.torrentInbox, { withFileTypes: true });
    const torrents = [];

    for (const entry of entries) {
        const fullPath = path.join(config.torrentInbox, entry.name);

        if (entry.isDirectory()) {
            if (fullPath !== config.torrentArchive) {
                logger.info('inbox', 'ignoring directory in torrent inbox', { path: fullPath });
            }
            continue;
        }

        if (entry.isFile() && entry.name.toLowerCase().endsWith('.torrent')) {
            torrents.push(fullPath);
        }
        else {
            logger.info('inbox', 'ignoring non-torrent inbox file', { path: fullPath });
        }
    }

    return torrents;
}

export async function archiveTorrentFile(filePath, config, logger) {
    const parsedPath = path.parse(filePath);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const archiveName = `${sanitizeSegment(parsedPath.name)}-${timestamp}${parsedPath.ext}`;
    const destination = path.join(config.torrentArchive, archiveName);

    if (config.dryRun) {
        logger.info('inbox', 'dry-run would archive torrent file', { source: filePath, destination });

        return destination;
    }

    await fs.rename(filePath, destination);
    logger.info('inbox', 'archived torrent file', { source: filePath, destination });

    return destination;
}

export function sourcePathForTorrentFile(torrent, file, config) {
    const relativeDownloadDir = path.posix.relative(config.transmissionDownloadDir, torrent.downloadDir || config.transmissionDownloadDir);
    const relativeFile = file.name || '';
    const relativePath = relativeDownloadDir && relativeDownloadDir !== '.' ? path.join(relativeDownloadDir, relativeFile) : relativeFile;

    return path.join(config.transmissionBooksPath, relativePath);
}

export async function scanTorrentFiles(torrent, config, logger, summary) {
    const candidates = [];
    const seen = new Set();
    const roots = await inferTorrentScanRoots(torrent, config);

    for (const root of roots) {
        try {
            const stats = await fs.stat(root.sourcePath);

            if (stats.isDirectory()) {
                await walkCandidateFiles(root.sourcePath, root.relativePath, torrent, config, logger, summary, candidates, seen);
            }
            else if (stats.isFile()) {
                await evaluateSourceFile(root.sourcePath, root.relativePath, torrent, config, logger, summary, candidates, seen);
            }
        }
        catch {
            logger.warn('scan', 'source path from completed torrent does not exist yet', { torrent: torrent.name, path: root.sourcePath });
            summary.filesSkipped += 1;
        }
    }

    return candidates;
}

export async function inferTorrentScanRoots(torrent, config) {
    const files = Array.isArray(torrent.files) && torrent.files.length > 0 ? torrent.files : [{ name: torrent.name }];
    const relativeDownloadDir = path.posix.relative(config.transmissionDownloadDir, torrent.downloadDir || config.transmissionDownloadDir);
    const torrentNameRoot = path.join(config.transmissionBooksPath, relativeDownloadDir === '.' ? '' : relativeDownloadDir, torrent.name || '');

    try {
        const stats = await fs.stat(torrentNameRoot);

        if (stats.isDirectory()) {
            return [{ sourcePath: torrentNameRoot, relativePath: sanitizeSegment(torrent.name) }];
        }
    }
    catch {
        // Continue to file-list roots.
    }

    const topLevelParts = files
        .map((file) => String(file.name || '').split(/[\\/]+/).filter(Boolean)[0])
        .filter(Boolean);
    const uniqueTopLevelParts = [...new Set(topLevelParts)];

    if (uniqueTopLevelParts.length === 1 && files.length > 1) {
        const root = sourcePathForTorrentFile(torrent, { name: uniqueTopLevelParts[0] }, config);

        return [{ sourcePath: root, relativePath: uniqueTopLevelParts[0] }];
    }

    return files.map((file) => ({
        sourcePath: sourcePathForTorrentFile(torrent, file, config),
        relativePath: file.name || path.basename(sourcePathForTorrentFile(torrent, file, config)),
    }));
}

async function walkCandidateFiles(rootPath, rootRelativePath, torrent, config, logger, summary, candidates, seen) {
    const entries = await fs.readdir(rootPath, { withFileTypes: true });

    for (const entry of entries) {
        const sourcePath = path.join(rootPath, entry.name);
        const relativePath = path.join(rootRelativePath, entry.name);

        if (entry.isDirectory()) {
            await walkCandidateFiles(sourcePath, relativePath, torrent, config, logger, summary, candidates, seen);
            continue;
        }

        if (entry.isFile()) {
            await evaluateSourceFile(sourcePath, relativePath, torrent, config, logger, summary, candidates, seen);
        }
    }
}

async function evaluateSourceFile(sourcePath, relativePath, torrent, config, logger, summary, candidates, seen) {
    if (seen.has(sourcePath)) {
        return;
    }

    seen.add(sourcePath);
    const stats = await fs.stat(sourcePath);
    const classification = classifyPath(sourcePath, config);

    if (stats.size === 0) {
        summary.filesSkipped += 1;
        logger.info('scan', 'skipping zero-byte file', { path: sourcePath });
        return;
    }

    if (classification.kind === 'archive') {
        summary.archivesIgnored += 1;
        logger.info('scan', 'ignored compressed archive without extraction', { path: sourcePath });
        return;
    }

    if (classification.kind !== 'supported') {
        summary.filesSkipped += 1;
        logger.info('scan', 'skipping unsupported source file', { path: sourcePath, reason: classification.reason });
        return;
    }

    candidates.push({
        torrent,
        sourcePath,
        relativePath,
        size: stats.size,
        mtimeMs: Math.trunc(stats.mtimeMs),
        extension: path.extname(sourcePath).toLowerCase(),
    });
}

export function planDestination(candidate, classification, config) {
    const fileName = sanitizeSegment(path.basename(candidate.sourcePath), 'book-file');
    const baseDir = classification.confident
        ? path.join(config.booksDest, sanitizeSegment(classification.author), sanitizeSegment(classification.title))
        : path.join(config.needsReviewDir, sanitizeSegment(classification.reviewName || candidate.torrent.name));

    return path.join(baseDir, fileName);
}

export async function resolveCollision(destination, candidate, logger) {
    try {
        const stats = await fs.stat(destination);

        if (stats.size === candidate.size) {
            return { destination, action: 'already-present' };
        }
    }
    catch {
        return { destination, action: 'copy' };
    }

    const parsedPath = path.parse(destination);
    const suffix = String(candidate.torrent.hashString || Buffer.from(candidate.sourcePath).toString('hex')).slice(0, 8);

    for (let index = 0; index < 100; index += 1) {
        const counter = index === 0 ? '' : `-${index + 1}`;
        const collisionDestination = path.join(parsedPath.dir, `${parsedPath.name} (${suffix}${counter})${parsedPath.ext}`);

        try {
            const stats = await fs.stat(collisionDestination);

            if (stats.size === candidate.size) {
                logger.warn('copy', 'destination collision suffix already exists with same size; recording as already present', { destination, collisionDestination });

                return { destination: collisionDestination, action: 'already-present' };
            }
        }
        catch {
            logger.warn('copy', 'destination exists with different size; using collision suffix', { destination, collisionDestination });

            return { destination: collisionDestination, action: 'copy-collision' };
        }
    }

    throw new Error(`Unable to find collision-safe destination for ${destination}`);
}

export async function copyCandidate(candidate, destination, config, logger) {
    await fs.mkdir(path.dirname(destination), { recursive: true });

    if (config.dryRun) {
        logger.info('copy', 'dry-run would copy source file', { source: candidate.sourcePath, destination });

        return false;
    }

    await fs.copyFile(candidate.sourcePath, destination, fs.constants.COPYFILE_EXCL);
    const mtime = new Date(candidate.mtimeMs);
    await fs.utimes(destination, mtime, mtime).catch((err) => {
        logger.warn('copy', 'failed to preserve destination timestamps', { destination, error: err.message });
    });

    return true;
}
