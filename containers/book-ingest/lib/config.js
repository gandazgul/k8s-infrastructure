export const SUPPORTED_EBOOK_EXTENSIONS = ['.epub', '.mobi', '.azw', '.azw3', '.pdf'];
export const SUPPORTED_MEDIA_EXTENSIONS = ['.mp3', '.m4a', '.m4b', '.mp4', '.flac', '.ogg', '.opus', '.wav', '.aac'];
export const IGNORED_ARCHIVE_EXTENSIONS = ['.zip', '.rar', '.7z', '.tar', '.tgz', '.tar.gz', '.gz', '.bz2', '.xz'];

function intFromEnv(env, key, fallback) {
    const rawValue = env[key];

    if (!rawValue) {
        return fallback;
    }

    const parsedValue = Number.parseInt(rawValue, 10);

    if (!Number.isFinite(parsedValue) || parsedValue < 1) {
        throw new Error(`${key} must be a positive integer`);
    }

    return parsedValue;
}

function boolFromEnv(env, key) {
    return ['1', 'true', 'yes'].includes(String(env[key] || '').toLowerCase());
}

export function loadConfig(env = process.env) {
    const config = {
        transmissionRpcUrl: env.TRANSMISSION_RPC_URL || 'http://transmission.default.svc.cluster.local:9091/transmission/rpc',
        transmissionRpcUsername: env.TRANSMISSION_RPC_USERNAME || '',
        transmissionRpcPassword: env.TRANSMISSION_RPC_PASSWORD || '',
        transmissionDownloadDir: env.TRANSMISSION_DOWNLOAD_DIR || '/data/books',
        transmissionBooksPath: env.TRANSMISSION_BOOKS_PATH || '/transmission/books',
        torrentInbox: env.TORRENT_INBOX || '/inbox',
        torrentArchive: env.TORRENT_ARCHIVE || '/inbox/archive',
        stateDir: env.STATE_DIR || '/state',
        booksDest: env.BOOKS_DEST || '/books',
        needsReviewDir: env.NEEDS_REVIEW_DIR || '/books/_needs-review',
        logLevel: env.LOG_LEVEL || 'info',
        metadataTimeoutMs: intFromEnv(env, 'METADATA_TIMEOUT_MS', 10000),
        dryRun: boolFromEnv(env, 'DRY_RUN'),
        supportedExtensions: new Set([...SUPPORTED_EBOOK_EXTENSIONS, ...SUPPORTED_MEDIA_EXTENSIONS]),
        ebookExtensions: new Set(SUPPORTED_EBOOK_EXTENSIONS),
        mediaExtensions: new Set(SUPPORTED_MEDIA_EXTENSIONS),
        ignoredArchiveExtensions: new Set(IGNORED_ARCHIVE_EXTENSIONS),
    };

    for (const [key, value] of Object.entries(config)) {
        if (typeof value === 'string' && value.trim() === '') {
            if (!['transmissionRpcUsername', 'transmissionRpcPassword'].includes(key)) {
                throw new Error(`${key} must not be empty`);
            }
        }
    }

    return config;
}
