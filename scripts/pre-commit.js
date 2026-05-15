#!/usr/bin/env node

/**
 * Pre-commit hook — JS-native replacement for pre-commit hooks.
 *
 * Checks:
 *   1. trailing-whitespace  — removes trailing whitespace from staged files
 *   2. end-of-file-fixer    — ensures files end with a single newline
 *   3. check-added-large-files — prevents committing files > 500 KB
 *
 * Exit code 0 = pass, 1 = fail (commit is aborted).
 */

import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const LARGE_FILE_SIZE_BYTES = 500 * 1024; // 500 KB

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getStagedFiles() {
    const out = execSync('git diff --cached --name-only --diff-filter=ACM', {
        encoding: 'utf-8',
    });

    return out
        .split('\n')
        .map((s) => s.trim())
        .filter(Boolean);
}

function isTextFile(filePath) {
    // Only process text-like extensions to avoid corrupting binaries
    const textExtensions = new Set([
        '.js', '.ts', '.json', '.yaml', '.yml', '.md', '.sh', '.bash',
        '.zsh', '.env', '.txt', '.cfg', '.conf', '.ini', '.toml',
        '.css', '.html', '.svg', '.xml', '.dockerfile', '.gitignore',
        '.gitattributes', '.editorconfig', '.npmrc', '.yarnrc',
    ]);

    const ext = path.extname(filePath).toLowerCase();

    return textExtensions.has(ext);
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

let hasErrors = false;

function error(msg) {
    console.error(`  ✖ ${msg}`);
    hasErrors = true;
}

function ok(msg) {
    console.log(`  ✓ ${msg}`);
}

/**
 * 1. trailing-whitespace — remove trailing whitespace from staged files.
 */
function checkTrailingWhitespace(files) {
    let modified = false;

    for (const file of files) {
        if (!isTextFile(file) || !fs.existsSync(file)) {
            continue;
        }

        const content = fs.readFileSync(file, 'utf-8');
        const lines = content.split('\n');
        const cleaned = lines.map((line) => line.replace(/\s+$/, ''));
        const newContent = cleaned.join('\n');

        if (newContent !== content) {
            fs.writeFileSync(file, newContent, 'utf-8');
            modified = true;
        }
    }

    if (modified) {
        ok('trailing-whitespace — fixed');
    }
    else {
        ok('trailing-whitespace — clean');
    }
}

/**
 * 2. end-of-file-fixer — ensure files end with exactly one newline.
 */
function checkEndOfFile(files) {
    let modified = false;

    for (const file of files) {
        if (!isTextFile(file) || !fs.existsSync(file)) {
            continue;
        }

        const content = fs.readFileSync(file, 'utf-8');

        // Remove trailing newlines, then add exactly one
        const trimmed = content.replace(/\n*$/, '');
        const fixed = trimmed + '\n';

        if (fixed !== content) {
            fs.writeFileSync(file, fixed, 'utf-8');
            modified = true;
        }
    }

    if (modified) {
        ok('end-of-file-fixer — fixed');
    }
    else {
        ok('end-of-file-fixer — clean');
    }
}

/**
 * 3. check-added-large-files — prevent committing files > 500 KB.
 */
function checkLargeFiles(files) {
    let found = false;

    for (const file of files) {
        if (!fs.existsSync(file)) {
            continue;
        }

        const stat = fs.statSync(file);

        if (stat.size > LARGE_FILE_SIZE_BYTES) {
            error(
                `check-added-large-files — ${file} is ${(stat.size / 1024).toFixed(1)} KB (max ${LARGE_FILE_SIZE_BYTES / 1024} KB)`
            );
            found = true;
        }
    }

    if (!found) {
        ok('check-added-large-files — clean');
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const stagedFiles = getStagedFiles();

if (stagedFiles.length === 0) {
    console.log('pre-commit: no staged files to check');
    process.exit(0);
}

console.log(`pre-commit: checking ${stagedFiles.length} staged file(s)\n`);

checkTrailingWhitespace(stagedFiles);
checkEndOfFile(stagedFiles);
checkLargeFiles(stagedFiles);

// Re-stage files that were auto-fixed (trailing-whitespace, end-of-file)
execSync(`git add ${stagedFiles.map((f) => `'${f}'`).join(' ')}`, {
    stdio: 'ignore',
});

console.log('');

if (hasErrors) {
    console.error('pre-commit: FAILED — fix errors above and try again');
    process.exit(1);
}

console.log('pre-commit: passed');
