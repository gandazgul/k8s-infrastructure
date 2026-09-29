import fs from 'node:fs/promises';
import path from 'node:path';

export class ImportState {
    constructor(stateFile, entries = []) {
        this.stateFile = stateFile;
        this.entries = entries;
        this.index = new Set(entries.map((entry) => ImportState.key(entry)));
    }

    static key(entry) {
        return `${entry.sourcePath}|${entry.fileSize}|${entry.mtimeMs}`;
    }

    has(candidate) {
        return this.index.has(ImportState.key({
            sourcePath: candidate.sourcePath,
            fileSize: candidate.size,
            mtimeMs: candidate.mtimeMs,
        }));
    }

    add(candidate, destinationPath) {
        const entry = {
            hashString: candidate.torrent.hashString || '',
            torrentName: candidate.torrent.name || '',
            sourcePath: candidate.sourcePath,
            sourceRelativePath: candidate.relativePath,
            fileSize: candidate.size,
            mtimeMs: candidate.mtimeMs,
            destinationPath,
            importedAt: new Date().toISOString(),
        };

        this.entries.push(entry);
        this.index.add(ImportState.key(entry));
    }

    async saveAtomic() {
        await fs.mkdir(path.dirname(this.stateFile), { recursive: true });
        const tempFile = `${this.stateFile}.${process.pid}.tmp`;
        const content = this.entries.map((entry) => JSON.stringify(entry)).join('\n');
        await fs.writeFile(tempFile, content ? `${content}\n` : '');
        await fs.rename(tempFile, this.stateFile);
    }
}

export async function loadImportState(config, logger) {
    const stateFile = path.join(config.stateDir, 'imported-files.jsonl');
    const entries = [];

    try {
        const content = await fs.readFile(stateFile, 'utf8');

        for (const [index, line] of content.split('\n').entries()) {
            if (!line.trim()) {
                continue;
            }

            try {
                entries.push(JSON.parse(line));
            }
            catch (err) {
                logger.warn('state', 'ignoring invalid state line', { line: index + 1, error: err.message });
            }
        }
    }
    catch (err) {
        if (err.code !== 'ENOENT') {
            throw err;
        }
    }

    logger.info('state', 'loaded imported-file state', { entries: entries.length, stateFile });

    return new ImportState(stateFile, entries);
}
