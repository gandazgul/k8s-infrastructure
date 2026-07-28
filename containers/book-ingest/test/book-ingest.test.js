import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { loadConfig } from '../lib/config.js';
import { classifyCandidateGroup, groupCandidates } from '../lib/classify.js';
import { classifyPath, planDestination, resolveCollision, sanitizeSegment } from '../lib/files.js';
import { ImportState } from '../lib/import-state.js';
import { isCompletedBookTorrent } from '../lib/transmission.js';

function baseConfig(overrides = {}) {
    return loadConfig({
        TRANSMISSION_RPC_URL: 'http://transmission/rpc',
        TRANSMISSION_DOWNLOAD_DIR: '/data/books',
        TRANSMISSION_BOOKS_PATH: '/transmission/books',
        TORRENT_INBOX: '/inbox',
        TORRENT_ARCHIVE: '/inbox/archive',
        STATE_DIR: '/state',
        BOOKS_DEST: '/books',
        NEEDS_REVIEW_DIR: '/books/_needs-review',
        ...overrides,
    });
}

function candidate(overrides = {}) {
    return {
        torrent: { name: 'Octavia Butler - Kindred', hashString: 'abcdef1234567890' },
        sourcePath: '/transmission/books/Octavia Butler - Kindred/Kindred.mp3',
        relativePath: 'Octavia Butler - Kindred/Kindred.mp3',
        size: 123,
        mtimeMs: 456,
        extension: '.mp3',
        ...overrides,
    };
}

test('sanitizes generated path segments without traversal or separators', () => {
    assert.equal(sanitizeSegment('../Bad/Name\u0000 With   Spaces'), '. Bad Name With Spaces');
    assert.equal(sanitizeSegment(''), 'unknown');
});

test('classifies supported, archive, temporary, and unsupported extensions', () => {
    const config = baseConfig();
    assert.equal(classifyPath('/books/file.epub', config).kind, 'supported');
    assert.equal(classifyPath('/books/file.tar.gz', config).kind, 'archive');
    assert.equal(classifyPath('/books/file.part', config).kind, 'temporary');
    assert.equal(classifyPath('/books/file.exe', config).kind, 'unsupported');
});

test('metadata confidence accepts consistent audiobook album grouping', () => {
    const candidates = [candidate({ sourcePath: '/a/01.mp3' }), candidate({ sourcePath: '/a/02.mp3' })];
    const metadata = new Map([
        ['/a/01.mp3', { author: 'Ursula Le Guin', album: 'A Wizard of Earthsea', title: 'Track 1' }],
        ['/a/02.mp3', { author: 'Ursula Le Guin', album: 'A Wizard of Earthsea', title: 'Track 2' }],
    ]);
    const result = classifyCandidateGroup(candidates, metadata);

    assert.equal(result.confident, true);
    assert.equal(result.author, 'Ursula Le Guin');
    assert.equal(result.title, 'A Wizard of Earthsea');
});

test('conflicting metadata routes to needs-review fallback', () => {
    const candidates = [candidate({ sourcePath: '/a/one.mp3', torrent: { name: 'Mystery', hashString: 'hash' } }), candidate({ sourcePath: '/a/two.mp3', torrent: { name: 'Mystery', hashString: 'hash' } })];
    const metadata = new Map([
        ['/a/one.mp3', { author: 'Author A', album: 'Book' }],
        ['/a/two.mp3', { author: 'Author B', album: 'Book' }],
    ]);
    const result = classifyCandidateGroup(candidates, metadata);
    const destination = planDestination(candidates[0], result, baseConfig());

    assert.equal(result.confident, false);
    assert.equal(destination, '/books/_needs-review/Mystery/one.mp3');
});

test('Author - Book heuristic creates confident destination when metadata is missing', () => {
    const result = classifyCandidateGroup([candidate()], new Map());

    assert.equal(result.confident, true);
    assert.equal(result.author, 'Octavia Butler');
    assert.equal(result.title, 'Kindred');
});

test('state is idempotent by source path, size, and modified time', () => {
    const state = new ImportState('/tmp/imported-files.jsonl');
    const first = candidate();
    const changed = candidate({ size: 124 });

    state.add(first, '/books/A/B/file.mp3');

    assert.equal(state.has(first), true);
    assert.equal(state.has(changed), false);
});

test('destination collision with same size is already-present and different size gets suffix', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'book-ingest-'));
    const destination = path.join(dir, 'Book.mp3');
    await fs.writeFile(destination, Buffer.alloc(123));

    assert.equal((await resolveCollision(destination, candidate(), console)).action, 'already-present');
    assert.equal((await resolveCollision(destination, candidate({ size: 10 }), console)).destination, path.join(dir, 'Book (abcdef12).mp3'));
});

test('destination collision suffix advances when first suffix also conflicts', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'book-ingest-'));
    const destination = path.join(dir, 'Book.mp3');
    await fs.writeFile(destination, Buffer.alloc(123));
    await fs.writeFile(path.join(dir, 'Book (abcdef12).mp3'), Buffer.alloc(122));

    assert.equal((await resolveCollision(destination, candidate({ size: 10 }), console)).destination, path.join(dir, 'Book (abcdef12-2).mp3'));
});

test('Transmission completed torrent filter requires /data/books and completion', () => {
    assert.equal(isCompletedBookTorrent({ downloadDir: '/data/books', percentDone: 1 }, '/data/books'), true);
    assert.equal(isCompletedBookTorrent({ downloadDir: '/data/movies', percentDone: 1 }, '/data/books'), false);
    assert.equal(isCompletedBookTorrent({ downloadDir: '/data/books', percentDone: 0.5, files: [{ length: 10 }], fileStats: [{ bytesCompleted: 10 }] }, '/data/books'), true);
});

test('groupCandidates groups audiobook tracks by containing folder', () => {
    const groups = groupCandidates([
        candidate({ relativePath: 'Author/Book/01.mp3' }),
        candidate({ relativePath: 'Author/Book/02.mp3' }),
    ]);

    assert.equal(groups.length, 1);
    assert.equal(groups[0].length, 2);
});
