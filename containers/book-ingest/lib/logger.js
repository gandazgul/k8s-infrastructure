const LEVELS = new Map([['debug', 10], ['info', 20], ['warn', 30], ['error', 40]]);

export function createLogger(logLevel = 'info') {
    const threshold = LEVELS.get(logLevel) || LEVELS.get('info');

    function log(level, area, message, context = {}) {
        if ((LEVELS.get(level) || 20) < threshold) {
            return;
        }

        const suffix = Object.keys(context).length > 0 ? ` ${JSON.stringify(context)}` : '';
        const line = `${level.toUpperCase()} ${area}: ${message}${suffix}`;

        if (level === 'error') {
            console.error(line);
        }
        else if (level === 'warn') {
            console.warn(line);
        }
        else {
            console.log(line);
        }
    }

    return {
        debug: (area, message, context) => log('debug', area, message, context),
        info: (area, message, context) => log('info', area, message, context),
        warn: (area, message, context) => log('warn', area, message, context),
        error: (area, message, context) => log('error', area, message, context),
        summary: (summary) => log('info', 'summary', 'book ingest finished', summary),
    };
}
