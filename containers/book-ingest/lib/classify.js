import path from 'node:path';
import { sanitizeSegment } from './files.js';

function clean(value) {
    return sanitizeSegment(value, '').trim();
}

function unique(values) {
    return [...new Set(values.map(clean).filter(Boolean).map((value) => value.toLowerCase()))];
}

export function classifyCandidateGroup(candidates, metadataBySource) {
    const authors = [];
    const titles = [];
    const albumTitles = [];

    for (const candidate of candidates) {
        const metadata = metadataBySource.get(candidate.sourcePath) || {};
        const author = clean(metadata.author);
        const title = clean(metadata.title);
        const album = clean(metadata.album);

        if (author) {
            authors.push(author);
        }

        if (album) {
            albumTitles.push(album);
        }

        if (title) {
            titles.push(title);
        }
    }

    const uniqueAuthors = unique(authors);
    const preferredTitles = albumTitles.length > 0 ? albumTitles : titles;
    const uniqueTitles = unique(preferredTitles);

    if (uniqueAuthors.length === 1 && uniqueTitles.length === 1) {
        return {
            confident: true,
            author: authors.find((author) => clean(author).toLowerCase() === uniqueAuthors[0]),
            title: preferredTitles.find((title) => clean(title).toLowerCase() === uniqueTitles[0]),
            reason: 'consistent metadata',
        };
    }

    const heuristic = classifyByPathHeuristics(candidates);

    if (heuristic.confident) {
        return heuristic;
    }

    return {
        confident: false,
        reviewName: candidates[0]?.torrent?.name || path.basename(candidates[0]?.sourcePath || 'unknown'),
        reason: 'missing or conflicting metadata and heuristics',
    };
}

export function classifyByPathHeuristics(candidates) {
    const first = candidates[0];

    if (!first) {
        return { confident: false };
    }

    const relativeParts = first.relativePath.split(/[\\/]+/).filter(Boolean).map((part) => clean(part));
    const torrentParts = clean(first.torrent.name).split(/[\\/]+/).filter(Boolean).map((part) => clean(part));
    const candidateParts = relativeParts.length >= 3 ? relativeParts : torrentParts;

    if (candidateParts.length >= 2) {
        const author = candidateParts.at(-3) || candidateParts.at(-2);
        const title = candidateParts.at(-2) || path.parse(candidateParts.at(-1)).name;

        if (author && title && author.toLowerCase() !== title.toLowerCase()) {
            return { confident: true, author, title, reason: 'Author/Book folder heuristic' };
        }
    }

    const namesToTry = [clean(first.torrent.name), clean(path.parse(first.relativePath).name)];

    for (const name of namesToTry) {
        const match = name.match(/^(.+?)\s+-\s+(.+)$/);

        if (match) {
            return { confident: true, author: clean(match[1]), title: clean(match[2]), reason: 'Author - Book name heuristic' };
        }
    }

    return { confident: false };
}

export function groupCandidates(candidates) {
    const groups = new Map();

    for (const candidate of candidates) {
        const dirname = path.dirname(candidate.relativePath || candidate.sourcePath);
        const key = dirname === '.' ? candidate.torrent.hashString || candidate.torrent.name : `${candidate.torrent.hashString || candidate.torrent.name}:${dirname}`;

        if (!groups.has(key)) {
            groups.set(key, []);
        }

        groups.get(key).push(candidate);
    }

    return [...groups.values()];
}
