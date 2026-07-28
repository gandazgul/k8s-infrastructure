function buildHeaders(config, sessionId) {
    const headers = { 'Content-Type': 'application/json' };

    if (sessionId) {
        headers['X-Transmission-Session-Id'] = sessionId;
    }

    if (config.transmissionRpcUsername || config.transmissionRpcPassword) {
        const token = Buffer.from(`${config.transmissionRpcUsername}:${config.transmissionRpcPassword}`).toString('base64');
        headers.Authorization = `Basic ${token}`;
    }

    return headers;
}

export class TransmissionClient {
    constructor(config, logger) {
        this.config = config;
        this.logger = logger;
        this.sessionId = '';
    }

    async request(method, args = {}) {
        const body = JSON.stringify({ method, arguments: args });
        let response = await fetch(this.config.transmissionRpcUrl, {
            method: 'POST',
            headers: buildHeaders(this.config, this.sessionId),
            body,
        });

        if (response.status === 409) {
            this.sessionId = response.headers.get('x-transmission-session-id') || '';
            this.logger.debug('transmission', 'refreshed rpc session id');
            response = await fetch(this.config.transmissionRpcUrl, {
                method: 'POST',
                headers: buildHeaders(this.config, this.sessionId),
                body,
            });
        }

        if (!response.ok) {
            throw new Error(`Transmission RPC ${method} failed with HTTP ${response.status}`);
        }

        const payload = await response.json();

        if (payload.result !== 'success') {
            throw new Error(`Transmission RPC ${method} failed: ${payload.result}`);
        }

        return payload.arguments || {};
    }

    async addTorrent(metainfo) {
        const args = await this.request('torrent-add', {
            metainfo,
            'download-dir': this.config.transmissionDownloadDir,
        });

        if (args['torrent-duplicate']) {
            return { status: 'duplicate', torrent: args['torrent-duplicate'] };
        }

        return { status: 'added', torrent: args['torrent-added'] };
    }

    async getCompletedBookTorrents() {
        const args = await this.request('torrent-get', {
            fields: ['id', 'name', 'hashString', 'downloadDir', 'percentDone', 'files', 'fileStats'],
        });
        const torrents = args.torrents || [];

        return torrents.filter((torrent) => isCompletedBookTorrent(torrent, this.config.transmissionDownloadDir));
    }
}

export function isCompletedBookTorrent(torrent, downloadDir) {
    const torrentDownloadDir = torrent.downloadDir || '';
    const underBooks = torrentDownloadDir === downloadDir || torrentDownloadDir.startsWith(`${downloadDir}/`);

    if (!underBooks) {
        return false;
    }

    if (torrent.percentDone >= 1) {
        return true;
    }

    const fileStats = Array.isArray(torrent.fileStats) ? torrent.fileStats : [];

    return fileStats.length > 0 && fileStats.every((stat, index) => {
        const file = torrent.files?.[index];

        return file && stat.bytesCompleted >= file.length;
    });
}
