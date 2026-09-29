import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

function clean(value) {
    if (Array.isArray(value)) {
        return value.map(clean).filter(Boolean).join(', ');
    }

    return String(value || '').replace(/\s+/g, ' ').trim();
}

async function runJson(command, args, timeoutMs, logger) {
    try {
        const { stdout } = await execFileAsync(command, args, { timeout: timeoutMs, maxBuffer: 1024 * 1024 });

        return stdout;
    }
    catch (err) {
        logger.warn('metadata', `${command} failed`, { file: args.at(-1), error: err.message });

        return '';
    }
}

export function parseEbookMetaOutput(stdout) {
    const metadata = {};

    for (const line of stdout.split('\n')) {
        const [rawKey, ...rest] = line.split(':');
        const key = clean(rawKey).toLowerCase();
        const value = clean(rest.join(':'));

        if (key === 'title' && value) {
            metadata.title = value;
        }

        if (key === 'author(s)' && value) {
            metadata.author = value;
        }
    }

    return metadata;
}

export function parseExifToolRecord(record, type) {
    if (!record) {
        return {};
    }

    const author = clean(record.AlbumArtist || record['Album Artist'] || record.Artist || record.Author || record.Creator || record.Byline);
    const album = clean(record.Album || record.Series || record.BookTitle);
    const title = clean(record.Title || record.DocumentTitle);

    if (type === 'media') {
        return {
            author,
            title: album || title,
            album,
            trackTitle: title,
        };
    }

    return {
        author,
        title,
    };
}

export function parseFfprobeTags(record) {
    const tags = record?.format?.tags || {};

    return {
        author: clean(tags.album_artist || tags.artist || tags.author),
        title: clean(tags.album || tags.title),
        album: clean(tags.album),
        trackTitle: clean(tags.title),
    };
}

function mergeTruthyMetadata(base, next) {
    const merged = { ...base };

    for (const [key, value] of Object.entries(next)) {
        if (clean(value)) {
            merged[key] = value;
        }
    }

    return merged;
}

export async function extractMetadata(filePath, config, logger) {
    const extension = path.extname(filePath).toLowerCase();
    const type = config.mediaExtensions.has(extension) ? 'media' : 'ebook';
    let metadata = {};

    if (type === 'ebook') {
        const stdout = await runJson('ebook-meta', [filePath], config.metadataTimeoutMs, logger);
        metadata = parseEbookMetaOutput(stdout);
    }

    if (!metadata.author || !metadata.title || type === 'media') {
        const stdout = await runJson('exiftool', ['-json', filePath], config.metadataTimeoutMs, logger);

        if (stdout) {
            try {
                metadata = mergeTruthyMetadata(metadata, parseExifToolRecord(JSON.parse(stdout)[0], type));
            }
            catch (err) {
                logger.warn('metadata', 'failed to parse exiftool json', { file: filePath, error: err.message });
            }
        }
    }

    if (type === 'media' && (!metadata.author || !metadata.album)) {
        const stdout = await runJson('ffprobe', ['-v', 'quiet', '-print_format', 'json', '-show_format', filePath], config.metadataTimeoutMs, logger);

        if (stdout) {
            try {
                metadata = mergeTruthyMetadata(metadata, parseFfprobeTags(JSON.parse(stdout)));
            }
            catch (err) {
                logger.warn('metadata', 'failed to parse ffprobe json', { file: filePath, error: err.message });
            }
        }
    }

    return metadata;
}
