import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { discoverIpv4, main, readConfig, updateDns } from './app.js';

const env = {
    CLUSTER_NAME: 'cerebro',
    CLUSTER_DOMAIN_NAME: 'example.test',
    CLOUDFLARE_API_TOKEN: 'offline-test-token',
    CLOUDFLARE_ZONE_ID: 'a'.repeat(32),
};
const config = readConfig(env);
const oldIp = '203.0.113.10';
const newIp = '203.0.113.20';
const record = {
    id: 'b'.repeat(32), type: 'A', name: config.name, content: oldIp,
    ttl: 1, proxied: true, comment: 'keep', tags: ['owner:ddns'],
    settings: { ipv4_only: true, ipv6_only: false }, modified_on: '2026-01-01T00:00:00Z',
};
const response = result => ({ success: true, result });
const listing = (records = [record], total = records.length) => ({
    ...response(records), result_info: { total_count: total, total_pages: Math.ceil(total / 2) },
});

function mockFetch(replies) {
    const calls = [];
    const fetchImpl = async (url, options) => {
        calls.push({ url, options });
        assert.ok(options.signal instanceof AbortSignal);
        assert.equal(options.redirect, 'error');
        assert.ok(replies.length, 'Unexpected request');
        const next = replies.shift();

        if (next instanceof Error) {
            throw next;
        }

        return next instanceof Response ? next : new Response(JSON.stringify(next));
    };

    return { calls, fetchImpl };
}

function captureLogs() {
    const messages = [];

    return { messages, logger: { log: (...args) => messages.push(args.join(' ')), error: (...args) => messages.push(args.join(' ')) } };
}

test('validates required inputs before any request; email is optional compatibility only', async () => {
    assert.equal(readConfig({ ...env, CLOUDFLARE_API_EMAIL: 'user@example.test' }).name, config.name);

    for (const invalid of [
        { CLUSTER_NAME: '' }, { CLUSTER_NAME: 'bad.name' }, { CLUSTER_DOMAIN_NAME: 'https://bad.test' },
        { CLOUDFLARE_API_TOKEN: '' }, { CLOUDFLARE_API_TOKEN: 'secret\ninjection' },
        { CLOUDFLARE_ZONE_ID: '../zone' }, { CLOUDFLARE_API_EMAIL: 'bad' }, { DRY_RUN: 'yes' },
    ]) {
        const logs = captureLogs();
        const { calls, fetchImpl } = mockFetch([]);
        assert.equal(await main({ env: { ...env, ...invalid }, fetchImpl, logger: logs.logger }), 1);
        assert.equal(calls.length, 0);
        assert.doesNotMatch(logs.messages.join(' '), /offline-test-token|secret/);
    }
});

test('same IP is a no-op with exact A/name query and no mutation', async () => {
    const { calls, fetchImpl } = mockFetch([listing()]);
    assert.equal(await updateDns(config, oldIp, fetchImpl), 'unchanged');
    assert.equal(calls.length, 1);
    const url = new URL(calls[0].url);
    assert.equal(url.searchParams.get('type'), 'A');
    assert.equal(url.searchParams.get('name'), config.name);
    assert.equal(url.searchParams.get('per_page'), '2');
    assert.equal(calls[0].options.headers.Authorization, `Bearer ${env.CLOUDFLARE_API_TOKEN}`);
});

test('only PATCHes content after immediate reread, preserves fields and verifies via GET', async () => {
    const updated = { ...record, content: newIp, modified_on: '2026-02-01T00:00:00Z' };
    const { calls, fetchImpl } = mockFetch([listing(), response(record), response(updated), response(updated)]);
    assert.equal(await updateDns(config, newIp, fetchImpl), 'updated');
    assert.deepEqual(calls.map(call => call.options.method || 'GET'), ['GET', 'GET', 'PATCH', 'GET']);
    assert.equal(calls[2].options.body, JSON.stringify({ content: newIp }));
    assert.equal(calls[1].url, calls[2].url);
    assert.equal(calls[2].url, calls[3].url);
});

test('missing, ambiguous, paginated, malformed, wrong-type and wrong-name results deny writes', async () => {
    for (const result of [
        listing([]), listing([record, { ...record, id: 'c'.repeat(32) }]), listing([record], 3),
        { ...listing(), result_info: undefined }, listing([{ ...record, type: 'AAAA' }]),
        listing([{ ...record, name: 'someone-else.example.test' }]),
        listing([{ ...record, id: '../bad' }]),
    ]) {
        const { calls, fetchImpl } = mockFetch([result]);
        await assert.rejects(updateDns(config, newIp, fetchImpl));
        assert.equal(calls.length, 1);
    }
});

test('concurrent changes to content, metadata, or properties deny writes', async () => {
    for (const change of [
        { content: '203.0.113.30' }, { ttl: 300 }, { proxied: false },
        { modified_on: '2026-02-01T00:00:00Z' }, { comment: 'someone changed this' },
    ]) {
        const { calls, fetchImpl } = mockFetch([listing(), response({ ...record, ...change })]);
        await assert.rejects(updateDns(config, newIp, fetchImpl), /changed before update/);
        assert.equal(calls.length, 2);
    }
});

test('readback must match IP and all preserved properties', async () => {
    for (const change of [
        { content: oldIp }, { ttl: 300 }, { proxied: false }, { settings: {} },
        { comment: '' }, { tags: [] }, { name: 'other.example.test' }, { id: 'c'.repeat(32) },
    ]) {
        const wrong = { ...record, content: newIp, ...change };
        const { calls, fetchImpl } = mockFetch([listing(), response(record), response(wrong), response(wrong)]);
        await assert.rejects(updateDns(config, newIp, fetchImpl));
        assert.equal(calls.length, 4);
    }
});

test('dry run performs only discovery and listing, and succeeds without PATCH', async () => {
    const { calls, fetchImpl } = mockFetch([new Response(newIp), listing()]);
    const logs = captureLogs();
    assert.equal(await main({ env: { ...env, DRY_RUN: 'true' }, fetchImpl, logger: logs.logger }), 0);
    assert.equal(calls.length, 2);
    assert.deepEqual(logs.messages, ['DDNS: dry-run.']);
});

test('discovery rejects bad IPv4, IPv6, oversized and failed providers within four attempts', async () => {
    const { calls, fetchImpl } = mockFetch([
        new Response('999.1.2.3'), new Response('::1'), new Response('x'.repeat(129)), new Error(`secret ${newIp}`),
    ]);
    await assert.rejects(discoverIpv4(fetchImpl), /discovery failed/);
    assert.equal(calls.length, 4);
    await assert.rejects(updateDns(config, '1.2.3.999', async () => assert.fail('must not fetch')), /Invalid discovered/);
});

test('discovery falls back on HTTP failure and trims valid IPv4', async () => {
    const { calls, fetchImpl } = mockFetch([new Response('failure', { status: 500 }), new Response(` ${newIp}\n`)]);
    assert.equal(await discoverIpv4(fetchImpl), newIp);
    assert.equal(calls.length, 2);
});

test('requests abort at their finite timeout, including discovery failures', async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    let attempts = 0;
    const pending = discoverIpv4(async (_url, { signal }) => {
        attempts += 1;

        return new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(new Error('timeout'))));
    });
    const rejected = assert.rejects(pending, /discovery failed/);

    for (let index = 0; index < 4; index += 1) {
        assert.equal(attempts, index + 1);
        t.mock.timers.tick(5000);
        await new Promise(resolve => setImmediate(resolve));
    }
    await rejected;
    assert.equal(attempts, 4);
});

test('request timeout covers a stalled response body, not just headers', async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    let attempts = 0;
    const pending = discoverIpv4(async (_url, { signal }) => {
        attempts += 1;

        return new Response(new ReadableStream({
            start(controller) {
                signal.addEventListener('abort', () => controller.error(new Error('body stalled')));
            },
        }));
    });
    const rejected = assert.rejects(pending, /discovery failed/);

    for (let index = 0; index < 4; index += 1) {
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(attempts, index + 1);
        t.mock.timers.tick(5000);
        await new Promise(resolve => setImmediate(resolve));
    }
    await rejected;
});

test('failures return nonzero and never log API bodies, exceptions, token, or IP', async () => {
    const secretError = new Error(`secret-body ${env.CLOUDFLARE_API_TOKEN} ${newIp}`);

    for (const replies of [
        Array(4).fill(secretError),
        [new Response(newIp), secretError],
        [new Response(newIp), { success: false, errors: [{ message: secretError.message }] }],
        [new Response(newIp), new Response(secretError.message)],
        [new Response(newIp), listing(), response(record), secretError],
        [new Response(newIp), listing(), response(record), response(record), response(record)],
    ]) {
        const logs = captureLogs();
        const { fetchImpl } = mockFetch(replies);
        assert.equal(await main({ env, fetchImpl, logger: logs.logger }), 1);
        assert.doesNotMatch(logs.messages.join(' '), /secret-body|offline-test-token|203\.0\.113/);
    }
});

test('successful main logs only outcome, never IP or full API response', async () => {
    const logs = captureLogs();
    const { fetchImpl } = mockFetch([new Response(oldIp), listing()]);
    assert.equal(await main({ env, fetchImpl, logger: logs.logger }), 0);
    assert.deepEqual(logs.messages, ['DDNS: unchanged.']);
});

test('CLI main gate exits nonzero on missing env before any network access', () => {
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('./app.js', import.meta.url))], {
        env: {}, encoding: 'utf8', timeout: 2000,
    });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, 'DDNS: Invalid CLUSTER_NAME.\n');
});

test('ConfigMap-like symlink entry point runs main while module imports stay inert', () => {
    const mount = mkdtempSync(join(tmpdir(), 'ddns-configmap-'));

    try {
        const dataDirectory = '..2026_11_02';
        mkdirSync(join(mount, dataDirectory));
        writeFileSync(join(mount, dataDirectory, 'app.mjs'), readFileSync(new URL('./app.js', import.meta.url)));
        symlinkSync(dataDirectory, join(mount, '..data'));
        symlinkSync('..data/app.mjs', join(mount, 'app.mjs'));
        const result = spawnSync(process.execPath, [join(mount, 'app.mjs')], {
            env: {}, encoding: 'utf8', timeout: 2000,
        });
        assert.equal(result.status, 1);
        assert.equal(result.stdout, '');
        assert.equal(result.stderr, 'DDNS: Invalid CLUSTER_NAME.\n');
        const imported = spawnSync(process.execPath, ['--input-type=module', '-e',
            'await import(process.env.TEST_IMPORT_PATH);'], {
            env: { TEST_IMPORT_PATH: join(mount, 'app.mjs') }, encoding: 'utf8', timeout: 2000,
        });
        assert.equal(imported.status, 0);
        assert.equal(imported.stdout, '');
        assert.equal(imported.stderr, '');
    }
    finally {
        rmSync(mount, { recursive: true, force: true });
    }
});
