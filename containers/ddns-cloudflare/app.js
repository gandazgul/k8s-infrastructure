import { isIP } from 'node:net';
import { realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const REQUEST_TIMEOUT_MS = 5000;
const IP_SERVICES = [
    'https://ifconfig.co/ip',
    'https://api.ipify.org',
    'https://icanhazip.com',
    'https://checkip.amazonaws.com',
];
const PRESERVED_FIELDS = ['id', 'type', 'name', 'ttl', 'proxied', 'settings', 'comment', 'tags'];

class UpdateError extends Error {}

function requireValid(condition, message) {

    if (!condition) {
        throw new UpdateError(message);
    }
}

export function readConfig(env) {
    const cluster = env.CLUSTER_NAME;
    const domain = env.CLUSTER_DOMAIN_NAME;
    const label = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
    requireValid(typeof cluster === 'string' && label.test(cluster), 'Invalid CLUSTER_NAME.');
    requireValid(typeof domain === 'string' && domain.length <= 253
        && domain.includes('.') && domain.split('.').every(part => label.test(part)), 'Invalid CLUSTER_DOMAIN_NAME.');
    const name = `${cluster}.clusters.${domain}`;
    requireValid(name.length <= 253, 'DNS record name is too long.');
    requireValid(typeof env.CLOUDFLARE_API_TOKEN === 'string'
        && /^[\x21-\x7e]+$/.test(env.CLOUDFLARE_API_TOKEN), 'Invalid CLOUDFLARE_API_TOKEN.');
    requireValid(/^[a-f0-9]{32}$/i.test(env.CLOUDFLARE_ZONE_ID || ''), 'Invalid CLOUDFLARE_ZONE_ID.');
    requireValid(!env.CLOUDFLARE_API_EMAIL || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(env.CLOUDFLARE_API_EMAIL),
        'Invalid CLOUDFLARE_API_EMAIL.');
    requireValid(env.DRY_RUN === undefined || ['true', 'false'].includes(env.DRY_RUN), 'Invalid DRY_RUN.');

    return { name, token: env.CLOUDFLARE_API_TOKEN, zoneId: env.CLOUDFLARE_ZONE_ID, dryRun: env.DRY_RUN === 'true' };
}

// The timeout covers headers AND body. Limit body size before parsing untrusted responses.
async function request(fetchImpl, url, options = {}, maxBytes = 65536) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
        const response = await fetchImpl(url, { ...options, signal: controller.signal, redirect: 'error' });
        requireValid(response.ok, 'HTTP request failed.');
        requireValid(response.body, 'Empty HTTP response.');
        const reader = response.body.getReader();
        const chunks = [];
        let length = 0;

        while (true) {
            const { done, value } = await reader.read();

            if (done) {
                break;
            }
            length += value.byteLength;
            requireValid(length <= maxBytes, 'HTTP response exceeds size limit.');
            chunks.push(Buffer.from(value));
        }

        return Buffer.concat(chunks).toString('utf8');
    }
    catch (error) {
        controller.abort();

        if (error instanceof UpdateError) {
            throw error;
        }
        throw new UpdateError('HTTP request failed or timed out.');
    }
    finally {
        clearTimeout(timer);
    }
}

export async function discoverIpv4(fetchImpl) {

    for (const service of IP_SERVICES) {
        try {
            const address = (await request(fetchImpl, service, {
                headers: { 'User-Agent': 'cloudflare-ddns/2.0' },
            }, 128)).trim();

            if (isIP(address) === 4) {
                return address;
            }
        }
        catch {
            // A provider failure permits only the next bounded, fixed provider.
        }
    }
    throw new UpdateError('Public IPv4 discovery failed.');
}

function canonical(value) {

    if (Array.isArray(value)) {
        return value.map(canonical);
    }

    if (value && typeof value === 'object') {
        return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
    }

    return value;
}

function same(left, right) {
    return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}

function validRecord(record, name) {
    requireValid(record && /^[a-f0-9]{32}$/i.test(record.id || '')
        && record.type === 'A' && record.name === name && isIP(record.content) === 4
        && Number.isInteger(record.ttl) && typeof record.proxied === 'boolean', 'Invalid DNS record.');

    return record;
}

export async function updateDns(config, address, fetchImpl) {
    requireValid(isIP(address) === 4, 'Invalid discovered IPv4.');
    const base = `https://api.cloudflare.com/client/v4/zones/${config.zoneId}/dns_records`;
    const headers = { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' };
    const api = async (suffix = '', options = {}) => {
        let payload;

        try {
            payload = JSON.parse(await request(fetchImpl, `${base}${suffix}`, { ...options, headers }));
        }
        catch {
            throw new UpdateError('Cloudflare request failed.');
        }
        requireValid(payload?.success === true && payload.result !== undefined, 'Cloudflare request failed.');

        return payload;
    };
    // Two results suffice to detect ambiguity; reject additional pages as well.
    const query = new URLSearchParams({ type: 'A', name: config.name, per_page: '2' });
    const listing = await api(`?${query}`);
    requireValid(Array.isArray(listing.result) && listing.result.length === 1
        && listing.result_info?.total_count === 1
        && listing.result_info?.total_pages === 1, 'Expected exactly one matching A record.');
    const original = validRecord(listing.result[0], config.name);

    if (original.content === address) {
        return 'unchanged';
    }

    if (config.dryRun) {
        return 'dry-run';
    }
    const suffix = `/${original.id}`;
    const latest = validRecord((await api(suffix)).result, config.name);
    // Compare the complete snapshot, including modified_on, immediately before PATCH.
    // An external writer can still race this GET: no atomic conditional write is used.
    requireValid(same(original, latest), 'DNS record changed before update; refusing to write.');
    await api(suffix, { method: 'PATCH', body: JSON.stringify({ content: address }) });
    const verified = validRecord((await api(suffix)).result, config.name);
    requireValid(verified.content === address
        && PRESERVED_FIELDS.every(field => same(original[field], verified[field])), 'DNS readback verification failed.');

    return 'updated';
}

export async function main({ env = process.env, fetchImpl = globalThis.fetch, logger = console } = {}) {
    try {
        const config = readConfig(env);
        requireValid(typeof fetchImpl === 'function', 'Runtime does not support fetch.');
        const address = await discoverIpv4(fetchImpl);
        const outcome = await updateDns(config, address, fetchImpl);
        logger.log(`DDNS: ${outcome}.`);

        return 0;
    }
    catch (error) {
        // Never log raw exceptions, IPs, tokens, or API responses.
        logger.error(`DDNS: ${error instanceof UpdateError ? error.message : 'Unexpected failure.'}`);

        return 1;
    }
}

// ConfigMap mounts expose the entry point through symlinks; ESM resolves its real path.
if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
    process.exitCode = await main();
}
