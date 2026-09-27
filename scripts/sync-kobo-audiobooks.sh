#!/bin/bash
set -e

ENV_FILE=".env.bookorbit"
DRY_RUN="false"
YES_DELETE="false"
EJECT_KOBO="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            ENV_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --yes-delete)
            YES_DELETE="true"
            shift
            ;;
        --eject)
            EJECT_KOBO="true"
            shift
            ;;
        -h|--help)
            printf "Usage: %s [--env .env.bookorbit] [--dry-run] [--yes-delete] [--eject]\n" "$0"
            exit 0
            ;;
        *)
            printf "Unknown argument: %s\n" "$1"
            exit 1
            ;;
    esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
    printf "Missing env file: %s\n" "${ENV_FILE}"
    exit 1
fi

while IFS= read -r ENV_LINE || [[ -n "${ENV_LINE}" ]]; do
    ENV_LINE="${ENV_LINE%$'\r'}"

    if [[ -z "${ENV_LINE}" || "${ENV_LINE}" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    ENV_LINE="${ENV_LINE#export }"

    if [[ ! "${ENV_LINE}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        printf "Invalid env line in %s: %s\n" "${ENV_FILE}" "${ENV_LINE}"
        exit 1
    fi

    ENV_KEY="${ENV_LINE%%=*}"
    ENV_VALUE="${ENV_LINE#*=}"
    ENV_VALUE="${ENV_VALUE#${ENV_VALUE%%[![:space:]]*}}"
    ENV_VALUE="${ENV_VALUE%${ENV_VALUE##*[![:space:]]}}"

    if [[ "${ENV_VALUE}" == \"*\" && "${ENV_VALUE}" == *\" ]]; then
        ENV_VALUE="${ENV_VALUE:1:${#ENV_VALUE}-2}"
    elif [[ "${ENV_VALUE}" == \'*\' && "${ENV_VALUE}" == *\' ]]; then
        ENV_VALUE="${ENV_VALUE:1:${#ENV_VALUE}-2}"
    fi

    export "${ENV_KEY}=${ENV_VALUE}"
done < "${ENV_FILE}"

BOOKORBIT_URL="${BOOKORBIT_URL%/}"
BOOKORBIT_COLLECTION="${BOOKORBIT_COLLECTION:-Kobo Audiobooks}"
BOOKORBIT_KOBO_VOLUME="${BOOKORBIT_KOBO_VOLUME:-/Volumes/KOBOeReader}"
BOOKORBIT_AUDIOBOOK_DIR="${BOOKORBIT_AUDIOBOOK_DIR:-${BOOKORBIT_KOBO_VOLUME}}"
BOOKORBIT_STATE_DIR="${BOOKORBIT_STATE_DIR:-${BOOKORBIT_KOBO_VOLUME}}"
BOOKORBIT_TRASH_DIR="${BOOKORBIT_TRASH_DIR:-${BOOKORBIT_STATE_DIR}/.bookorbit-trash}"
BOOKORBIT_AUDIO_GAIN_DB="${BOOKORBIT_AUDIO_GAIN_DB:-${AUDIO_GAIN_DB:-8}}"
BOOKORBIT_AUDIO_BITRATE="${BOOKORBIT_AUDIO_BITRATE:-${AUDIO_BITRATE:-96k}}"

if [[ -z "${BOOKORBIT_URL}" ]]; then
    printf "BOOKORBIT_URL is required in %s\n" "${ENV_FILE}"
    exit 1
fi

if [[ -z "${BOOKORBIT_TOKEN:-}" && -z "${BOOKORBIT_MAGIC_LINK_TOKEN:-}" ]]; then
    if [[ -z "${BOOKORBIT_USERNAME:-}" || -z "${BOOKORBIT_PASSWORD:-}" ]]; then
        printf "Set BOOKORBIT_TOKEN, BOOKORBIT_MAGIC_LINK_TOKEN, or BOOKORBIT_USERNAME and BOOKORBIT_PASSWORD in %s\n" "${ENV_FILE}"
        exit 1
    fi
fi

if [[ ! -d "${BOOKORBIT_KOBO_VOLUME}/.kobo" ]]; then
    printf "This does not look like a mounted Kobo volume: %s\n" "${BOOKORBIT_KOBO_VOLUME}"
    printf "Missing directory: %s/.kobo\n" "${BOOKORBIT_KOBO_VOLUME}"
    exit 1
fi

for COMMAND in curl python3; do
    if ! command -v "${COMMAND}" >/dev/null 2>&1; then
        printf "%s is required. Install it and run again.\n" "${COMMAND}"
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CREATE_AUDIOBOOK_SCRIPT="${REPO_ROOT}/scripts/create-kobo-audiobook.sh"

if [[ ! -x "${CREATE_AUDIOBOOK_SCRIPT}" ]]; then
    printf "Missing executable script: %s\n" "${CREATE_AUDIOBOOK_SCRIPT}"
    printf "Run: chmod +x %s\n" "${CREATE_AUDIOBOOK_SCRIPT}"
    exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

ensure_kobo_audiobook_dir() {
    if [[ ! -d "${BOOKORBIT_KOBO_VOLUME}/.kobo" ]]; then
        printf "Kobo volume is not available: %s\n" "${BOOKORBIT_KOBO_VOLUME}"
        printf "Missing directory: %s/.kobo\n" "${BOOKORBIT_KOBO_VOLUME}"
        printf "Reconnect the Kobo, then run this script again. Already copied books will be skipped.\n"
        exit 1
    fi

    mkdir -p "${BOOKORBIT_AUDIOBOOK_DIR}"
    mkdir -p "${BOOKORBIT_STATE_DIR}"
    mkdir -p "${BOOKORBIT_TRASH_DIR}"

    if [[ ! -w "${BOOKORBIT_AUDIOBOOK_DIR}" ]]; then
        printf "Kobo audiobook folder is not writable: %s\n" "${BOOKORBIT_AUDIOBOOK_DIR}"
        printf "Reconnect the Kobo, then run this script again. Already copied books will be skipped.\n"
        exit 1
    fi

    if [[ ! -w "${BOOKORBIT_STATE_DIR}" ]]; then
        printf "Kobo state folder is not writable: %s\n" "${BOOKORBIT_STATE_DIR}"
        printf "Reconnect the Kobo, then run this script again. Already copied books will be skipped.\n"
        exit 1
    fi
}

copy_to_audiobook_dir() {
    local output_file="$1"
    local output_name="$2"
    local target_file="${BOOKORBIT_AUDIOBOOK_DIR}/${output_name}"
    local temp_file="${BOOKORBIT_AUDIOBOOK_DIR}/.${output_name}.tmp"

    if [[ ! -f "${output_file}" ]]; then
        printf "Converted audiobook was not created: %s\n" "${output_file}"
        exit 1
    fi

    ensure_kobo_audiobook_dir
    rm -f "${temp_file}"

    if ! cp "${output_file}" "${temp_file}"; then
        rm -f "${temp_file}"
        printf "Failed to copy audiobook to Kobo folder: %s\n" "${BOOKORBIT_AUDIOBOOK_DIR}"
        printf "Reconnect the Kobo, then run this script again. Already copied books will be skipped.\n"
        exit 1
    fi

    sync

    if ! mv "${temp_file}" "${target_file}"; then
        rm -f "${temp_file}"
        printf "Failed to finish Kobo audiobook copy: %s\n" "${target_file}"
        printf "Reconnect the Kobo, then run this script again. Already copied books will be skipped.\n"
        exit 1
    fi

    rm -f "${output_file}"
}

ensure_kobo_audiobook_dir

MANIFEST_PATH="${BOOKORBIT_STATE_DIR}/.bookorbit-sync.json"
LEGACY_MANIFEST_PATH="${BOOKORBIT_KOBO_VOLUME}/audiobooks-bookorbit/.bookorbit-sync.json"
if [[ ! -f "${MANIFEST_PATH}" && -f "${LEGACY_MANIFEST_PATH}" ]]; then
    cp "${LEGACY_MANIFEST_PATH}" "${MANIFEST_PATH}"
fi
DESIRED_JSON="${WORK_DIR}/desired.json"
PLAN_JSON="${WORK_DIR}/plan.json"
TOKEN_FILE="${WORK_DIR}/token"
BUILT_IDS="${WORK_DIR}/built-ids.txt"
DELETED_IDS="${WORK_DIR}/deleted-ids.txt"
touch "${BUILT_IDS}" "${DELETED_IDS}"

python3 - "${DESIRED_JSON}" "${TOKEN_FILE}" <<'PY'
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
import json
import os
import re
import sys

out_path = Path(sys.argv[1])
token_path = Path(sys.argv[2])
base_url = os.environ["BOOKORBIT_URL"].rstrip("/")
collection_name = os.environ.get("BOOKORBIT_COLLECTION", "Kobo Audiobooks")
audio_formats = {"m4b", "m4a", "mp3", "opus", "ogg", "flac", "aac", "wav"}
priority = {"m4b": 0, "m4a": 1, "mp3": 2, "opus": 3, "ogg": 4, "flac": 5, "aac": 6, "wav": 7}


def request_json(method, path, token=None, body=None):
    url = f"{base_url}{path}"
    data = None
    headers = {"accept": "application/json"}

    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["content-type"] = "application/json"

    if token:
        headers["authorization"] = f"Bearer {token}"

    req = Request(url, data=data, headers=headers, method=method)

    try:
        with urlopen(req, timeout=60) as response:
            raw = response.read().decode("utf-8")
    except HTTPError as err:
        detail = err.read().decode("utf-8", errors="replace")
        raise SystemExit(f"BookOrbit API error {err.code} for {path}: {detail}") from err
    except URLError as err:
        raise SystemExit(f"BookOrbit API connection failed for {path}: {err}") from err

    return json.loads(raw) if raw else None


def login():
    token = os.environ.get("BOOKORBIT_TOKEN", "").strip()
    if token:
        return token

    magic_token = os.environ.get("BOOKORBIT_MAGIC_LINK_TOKEN", "").strip()
    if magic_token:
        data = request_json("POST", "/api/v1/auth/magic-links/login", body={"token": magic_token})
    else:
        data = request_json(
            "POST",
            "/api/v1/auth/login",
            body={
                "username": os.environ["BOOKORBIT_USERNAME"],
                "password": os.environ["BOOKORBIT_PASSWORD"],
            },
        )

    access_token = (data or {}).get("accessToken")
    if not access_token:
        raise SystemExit("BookOrbit login did not return accessToken")

    return access_token


def as_items(value):
    if isinstance(value, list):
        return value

    if isinstance(value, dict):
        for key in ("items", "collections", "data"):
            if isinstance(value.get(key), list):
                return value[key]

    return []


def safe_filename(value):
    cleaned = re.sub(r"[\\/:*?\"<>|]+", "-", value)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return cleaned[:180] or "audiobook"


def book_authors(book):
    authors = book.get("authors") or []
    if isinstance(authors, list):
        return [str(author) for author in authors if str(author).strip()]

    if isinstance(authors, str) and authors.strip():
        return [authors.strip()]

    return []


def choose_audio_file(book):
    files = book.get("files") or []
    candidates = []

    for file_ref in files:
        if not isinstance(file_ref, dict):
            continue

        fmt = str(file_ref.get("format") or "").lower().lstrip(".")
        role = str(file_ref.get("role") or "").lower()
        filename = str(file_ref.get("filename") or "")
        suffix = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        resolved_format = fmt or suffix

        if resolved_format in audio_formats or role == "audio":
            candidates.append((priority.get(resolved_format, 99), file_ref, resolved_format or "audio"))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0])
    return candidates[0][1], candidates[0][2]


token = login()
token_path.write_text(token, encoding="utf-8")
collections_response = request_json("GET", "/api/v1/collections", token=token)
collections = as_items(collections_response)
collection = None

for item in collections:
    name = item.get("name") or item.get("title")
    if name == collection_name:
        collection = item
        break

if not collection:
    found = ", ".join(str(item.get("name") or item.get("title") or item.get("id")) for item in collections)
    raise SystemExit(f"Collection not found: {collection_name}. Found: {found}")

collection_id = collection.get("id")
if collection_id is None:
    raise SystemExit(f"Collection has no id: {collection_name}")

books = []
page = 0
size = 100

while True:
    response = request_json("GET", f"/api/v1/collections/{quote(str(collection_id))}/books?page={page}&size={size}", token=token)
    items = as_items(response)
    books.extend(items)

    if not isinstance(response, dict):
        break

    total = int(response.get("total") or len(books))
    if len(books) >= total or not items:
        break

    page += 1

desired = []
skipped_no_audio = []

for book in books:
    selected = choose_audio_file(book)
    if not selected:
        skipped_no_audio.append({"id": book.get("id"), "title": book.get("title")})
        continue

    file_ref, file_format = selected
    book_id = book.get("id")
    file_id = file_ref.get("id")
    title = str(book.get("title") or f"Book {book_id}")
    authors = book_authors(book)
    display_name = f"{title} - {', '.join(authors)}" if authors else title
    filename = f"{safe_filename(display_name)}.mp3z"
    size_bytes = file_ref.get("sizeBytes")
    signature = f"book:{book_id}|file:{file_id}|format:{file_format}|size:{size_bytes}|updated:{book.get('updatedAt')}"
    desired.append(
        {
            "bookId": book_id,
            "fileId": file_id,
            "title": title,
            "authors": authors,
            "format": file_format,
            "sizeBytes": size_bytes,
            "updatedAt": book.get("updatedAt"),
            "filename": filename,
            "signature": signature,
        }
    )

out_path.write_text(json.dumps({"collection": collection, "books": desired, "skippedNoAudio": skipped_no_audio}, indent=2) + "\n", encoding="utf-8")
PY
chmod 600 "${TOKEN_FILE}"

python3 - "${DESIRED_JSON}" "${MANIFEST_PATH}" "${BOOKORBIT_AUDIOBOOK_DIR}" "${PLAN_JSON}" <<'PY'
from pathlib import Path
import json
import sys
import zipfile

desired_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
managed_dir = Path(sys.argv[3])
plan_path = Path(sys.argv[4])
desired_data = json.loads(desired_path.read_text(encoding="utf-8"))
desired = desired_data.get("books", [])

if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
else:
    manifest = {"books": []}

current_by_book = {str(item.get("bookId")): item for item in manifest.get("books", [])}
desired_by_book = {str(item.get("bookId")): item for item in desired}
build = []
skip = []
stale = []


def is_complete_mp3z(path):
    try:
        with zipfile.ZipFile(path) as archive:
            return any(name.lower().endswith(".mp3") for name in archive.namelist())
    except zipfile.BadZipFile:
        return False

for item in desired:
    key = str(item.get("bookId"))
    current = current_by_book.get(key)
    target = managed_dir / item["filename"]

    if target.exists() and is_complete_mp3z(target) and (not current or current.get("signature") == item.get("signature")):
        skip.append(item)
    else:
        build.append(item)

for key, item in current_by_book.items():
    filename = item.get("filename")
    if key not in desired_by_book and filename and (managed_dir / filename).exists():
        stale.append(item)

plan = {
    "collection": desired_data.get("collection"),
    "build": build,
    "skip": skip,
    "stale": stale,
    "skippedNoAudio": desired_data.get("skippedNoAudio", []),
    "desired": desired,
    "current": manifest.get("books", []),
}
plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")

print(f"Collection: {desired_data.get('collection', {}).get('name') or desired_data.get('collection', {}).get('title')}")
print(f"Desired audio books: {len(desired)}")
print(f"Already synced: {len(skip)}")
print(f"To build/copy: {len(build)}")
print(f"To remove from Kobo root: {len(stale)}")

if plan["skippedNoAudio"]:
    print("Books skipped because no audio file was found:")
    for item in plan["skippedNoAudio"]:
        print(f"  - {item.get('title') or item.get('id')}")
PY

if [[ "${DRY_RUN}" = "true" ]]; then
    printf "Dry run only. No files were downloaded, converted, deleted, or ejected.\n"
    exit 0
fi

BUILD_COUNT="$(python3 - "${PLAN_JSON}" <<'PY'
import json
import sys
print(len(json.loads(open(sys.argv[1], encoding="utf-8").read()).get("build", [])))
PY
)"

for ((INDEX = 0; INDEX < BUILD_COUNT; INDEX++)); do
    ITEM_JSON="${WORK_DIR}/item-${INDEX}.json"
    python3 - "${PLAN_JSON}" "${INDEX}" "${ITEM_JSON}" <<'PY'
from pathlib import Path
import json
import sys

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
item = plan["build"][int(sys.argv[2])]
Path(sys.argv[3]).write_text(json.dumps(item) + "\n", encoding="utf-8")
PY

    BOOK_ID="$(python3 - "${ITEM_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["bookId"])
PY
)"
    FILE_ID="$(python3 - "${ITEM_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["fileId"])
PY
)"
    TITLE="$(python3 - "${ITEM_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["title"])
PY
)"
    FORMAT="$(python3 - "${ITEM_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read()).get("format") or "audio")
PY
)"
    OUTPUT_NAME="$(python3 - "${ITEM_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["filename"])
PY
)"

    SOURCE_FILE="${WORK_DIR}/book-${BOOK_ID}.${FORMAT}"
    OUTPUT_FILE="${WORK_DIR}/${OUTPUT_NAME}"
    TOKEN="$(cat "${TOKEN_FILE}")"

    printf "Downloading: %s\n" "${TITLE}"
    curl -fL --retry 3 --retry-delay 2 \
        -H "authorization: Bearer ${TOKEN}" \
        -o "${SOURCE_FILE}" \
        "${BOOKORBIT_URL}/api/v1/books/files/${FILE_ID}/download"

    printf "Converting for Kobo: %s\n" "${TITLE}"
    AUDIO_GAIN_DB="${BOOKORBIT_AUDIO_GAIN_DB}" \
        AUDIO_BITRATE="${BOOKORBIT_AUDIO_BITRATE}" \
        "${CREATE_AUDIOBOOK_SCRIPT}" "${SOURCE_FILE}" "${OUTPUT_FILE}"

    copy_to_audiobook_dir "${OUTPUT_FILE}" "${OUTPUT_NAME}"
    printf "%s\n" "${BOOK_ID}" >> "${BUILT_IDS}"
    printf "Copied to Kobo root: %s/%s\n" "${BOOKORBIT_AUDIOBOOK_DIR}" "${OUTPUT_NAME}"
done

STALE_COUNT="$(python3 - "${PLAN_JSON}" <<'PY'
import json
import sys
print(len(json.loads(open(sys.argv[1], encoding="utf-8").read()).get("stale", [])))
PY
)"

if [[ "${STALE_COUNT}" != "0" ]]; then
    printf "Books no longer in the BookOrbit collection:\n"
    python3 - "${PLAN_JSON}" <<'PY'
import json
import sys
plan = json.loads(open(sys.argv[1], encoding="utf-8").read())
for item in plan.get("stale", []):
    print(f"  - {item.get('title') or item.get('bookId')} ({item.get('filename')})")
PY

    DELETE_ANSWER="n"
    if [[ "${YES_DELETE}" = "true" ]]; then
        DELETE_ANSWER="y"
    else
        printf "Move these files to .trash? [y/N] "
        read -r DELETE_ANSWER
    fi

    case "${DELETE_ANSWER}" in
        y|Y|yes|YES)
            TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
            for ((INDEX = 0; INDEX < STALE_COUNT; INDEX++)); do
                STALE_JSON="${WORK_DIR}/stale-${INDEX}.json"
                python3 - "${PLAN_JSON}" "${INDEX}" "${STALE_JSON}" <<'PY'
from pathlib import Path
import json
import sys
plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
item = plan["stale"][int(sys.argv[2])]
Path(sys.argv[3]).write_text(json.dumps(item) + "\n", encoding="utf-8")
PY
                OLD_NAME="$(python3 - "${STALE_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["filename"])
PY
)"
                OLD_BOOK_ID="$(python3 - "${STALE_JSON}" <<'PY'
import json
import sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["bookId"])
PY
)"
                if [[ -f "${BOOKORBIT_AUDIOBOOK_DIR}/${OLD_NAME}" ]]; then
                    mv "${BOOKORBIT_AUDIOBOOK_DIR}/${OLD_NAME}" "${BOOKORBIT_TRASH_DIR}/${TIMESTAMP}-${OLD_NAME}"
                    printf "%s\n" "${OLD_BOOK_ID}" >> "${DELETED_IDS}"
                    printf "Moved to trash: %s\n" "${OLD_NAME}"
                fi
            done
            ;;
        *)
            printf "No files removed. They will stay in the manifest.\n"
            ;;
    esac
fi

python3 - "${PLAN_JSON}" "${MANIFEST_PATH}" "${BUILT_IDS}" "${DELETED_IDS}" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import json
import sys

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
manifest_path = Path(sys.argv[2])
built_ids = {line.strip() for line in Path(sys.argv[3]).read_text(encoding="utf-8").splitlines() if line.strip()}
deleted_ids = {line.strip() for line in Path(sys.argv[4]).read_text(encoding="utf-8").splitlines() if line.strip()}
now = datetime.now(timezone.utc).isoformat()
desired = []

for item in plan.get("desired", []):
    row = dict(item)
    row["syncedAt"] = now
    desired.append(row)

kept_stale = [item for item in plan.get("stale", []) if str(item.get("bookId")) not in deleted_ids]
manifest = {
    "schemaVersion": 1,
    "updatedAt": now,
    "collection": plan.get("collection"),
    "books": desired + kept_stale,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

printf "Sync complete. Kobo audiobook folder: %s\n" "${BOOKORBIT_AUDIOBOOK_DIR}"

if [[ "${EJECT_KOBO}" = "true" ]]; then
    diskutil eject "${BOOKORBIT_KOBO_VOLUME}"
fi
