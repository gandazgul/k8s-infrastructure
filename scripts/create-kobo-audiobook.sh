#!/bin/bash
set -e

AUDIOBOOK_PATH="${1:-}"
OUTPUT_PATH="${2:-}"
KOBO_MOUNT_PATH="${KOBO_MOUNT_PATH:-}"
AUDIO_BITRATE="${AUDIO_BITRATE:-96k}"
AUDIO_GAIN_DB="${AUDIO_GAIN_DB:-0}"

if [[ -z "${AUDIOBOOK_PATH}" ]]; then
    printf "Usage: %s /path/to/audiobook-folder [output.mp3z]\n" "$0"
    printf "\n"
    printf "Optional environment variables:\n"
    printf "  KOBO_MOUNT_PATH=/Volumes/KOBOeReader  copy the mp3z to the Kobo\n"
    printf "  AUDIO_BITRATE=96k                    bitrate for converted audio\n"
    printf "  AUDIO_GAIN_DB=8                      optional volume boost in dB\n"
    printf "\n"
    exit 1
fi

if [[ ! -d "${AUDIOBOOK_PATH}" && ! -f "${AUDIOBOOK_PATH}" ]]; then
    printf "Audiobook path does not exist: %s\n" "${AUDIOBOOK_PATH}"
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    printf "zip is required. Install zip and run again.\n"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf "python3 is required. Install python3 and run again.\n"
    exit 1
fi

if [[ -n "${KOBO_MOUNT_PATH}" ]]; then
    if [[ ! -d "${KOBO_MOUNT_PATH}/.kobo" ]]; then
        printf "This does not look like a mounted Kobo volume: %s\n" "${KOBO_MOUNT_PATH}"
        printf "Missing directory: %s/.kobo\n" "${KOBO_MOUNT_PATH}"
        exit 1
    fi
fi

BOOK_NAME="$(basename "${AUDIOBOOK_PATH}")"
BOOK_NAME="${BOOK_NAME%.*}"
if [[ -z "${OUTPUT_PATH}" ]]; then
    OUTPUT_PATH="$(pwd)/${BOOK_NAME}.mp3z"
fi

case "${OUTPUT_PATH}" in
    *.mp3z) ;;
    *)
        printf "Output file must end with .mp3z: %s\n" "${OUTPUT_PATH}"
        exit 1
        ;;
esac

WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

SOURCE_LIST="${WORK_DIR}/sources.txt"
python3 - "${AUDIOBOOK_PATH}" "${SOURCE_LIST}" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
out = Path(sys.argv[2])
extensions = {".mp3", ".m4a", ".m4b", ".aac", ".flac", ".ogg", ".opus", ".wav"}

if root.is_file():
    files = [root] if root.suffix.lower() in extensions else []
else:
    files = sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in extensions
    )

out.write_text("\n".join(str(path) for path in files) + ("\n" if files else ""), encoding="utf-8")
PY

if [[ ! -s "${SOURCE_LIST}" ]]; then
    printf "No supported audio files found in: %s\n" "${AUDIOBOOK_PATH}"
    printf "Supported files: mp3, m4a, m4b, aac, flac, ogg, opus, wav\n"
    exit 1
fi

NEEDS_FFMPEG="false"
while IFS= read -r SOURCE_FILE; do
    LOWER_SOURCE_FILE="$(printf '%s' "${SOURCE_FILE}" | tr '[:upper:]' '[:lower:]')"

    case "${LOWER_SOURCE_FILE}" in
        *.mp3) ;;
        *) NEEDS_FFMPEG="true" ;;
    esac
done < "${SOURCE_LIST}"

if [[ "${NEEDS_FFMPEG}" = "true" ]] && ! command -v ffmpeg >/dev/null 2>&1; then
    printf "ffmpeg is required because at least one source file is not MP3.\n"
    printf "Install ffmpeg, or convert the audiobook to MP3 files first.\n"
    exit 1
fi

CHAPTER_DIR="${WORK_DIR}/chapters"
mkdir -p "${CHAPTER_DIR}"
CHAPTER_NUMBER=1
DID_CHAPTER_SPLIT="false"

if [[ -f "${AUDIOBOOK_PATH}" && "${NEEDS_FFMPEG}" = "true" ]]; then
    if ! command -v ffprobe >/dev/null 2>&1; then
        printf "ffprobe is required to inspect audiobook chapters. Install ffmpeg and run again.\n"
        exit 1
    fi

    CHAPTER_JSON="${WORK_DIR}/chapters.json"
    CHAPTER_LIST="${WORK_DIR}/chapters.tsv"
    ffprobe -v error -print_format json -show_chapters "${AUDIOBOOK_PATH}" > "${CHAPTER_JSON}"
    python3 - "${CHAPTER_JSON}" "${CHAPTER_LIST}" <<'PY'
from pathlib import Path
import json
import sys

source = Path(sys.argv[1])
out = Path(sys.argv[2])
data = json.loads(source.read_text(encoding="utf-8"))
chapters = data.get("chapters", [])

if len(chapters) < 2:
    out.write_text("", encoding="utf-8")
else:
    rows = []

    for chapter in chapters:
        rows.append(f"{chapter['start_time']}\t{chapter['end_time']}")

    out.write_text("\n".join(rows) + "\n", encoding="utf-8")
PY

    if [[ -s "${CHAPTER_LIST}" ]]; then
        printf "Splitting audiobook by embedded chapters.\n"
        python3 - \
            "${AUDIOBOOK_PATH}" \
            "${CHAPTER_LIST}" \
            "${CHAPTER_DIR}" \
            "${AUDIO_BITRATE}" \
            "${AUDIO_GAIN_DB}" <<'PY'
from pathlib import Path
import subprocess
import sys

source = sys.argv[1]
chapter_list = Path(sys.argv[2])
chapter_dir = Path(sys.argv[3])
bitrate = sys.argv[4]
gain_db = sys.argv[5]
filter_args = []

if gain_db != "0":
    filter_args = ["-af", f"volume={gain_db}dB,alimiter=limit=0.95"]

for index, line in enumerate(chapter_list.read_text(encoding="utf-8").splitlines(), start=1):
    start_time, end_time = line.split("\t", 1)
    chapter_file = chapter_dir / f"{index:04d}.mp3"
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            source,
            "-ss",
            start_time,
            "-to",
            end_time,
            "-vn",
            *filter_args,
            "-map_metadata",
            "-1",
            "-codec:a",
            "libmp3lame",
            "-b:a",
            bitrate,
            "-ar",
            "44100",
            "-ac",
            "2",
            str(chapter_file),
        ],
        check=True,
    )
PY

        DID_CHAPTER_SPLIT="true"
    fi
fi

if [[ "${DID_CHAPTER_SPLIT}" = "false" ]]; then
    while IFS= read -r SOURCE_FILE; do
        CHAPTER_FILE="${CHAPTER_DIR}/$(printf '%04d' "${CHAPTER_NUMBER}").mp3"
        LOWER_SOURCE_FILE="$(printf '%s' "${SOURCE_FILE}" | tr '[:upper:]' '[:lower:]')"

        case "${LOWER_SOURCE_FILE}" in
            *.mp3)
                cp "${SOURCE_FILE}" "${CHAPTER_FILE}"
                ;;
            *)
                ffmpeg -hide_banner -loglevel error -y \
                    -i "${SOURCE_FILE}" \
                    -vn \
                    -map_metadata -1 \
                    -codec:a libmp3lame \
                    -b:a "${AUDIO_BITRATE}" \
                    -ar 44100 \
                    -ac 2 \
                    "${CHAPTER_FILE}"
                ;;
        esac

        CHAPTER_NUMBER=$((CHAPTER_NUMBER + 1))
    done < "${SOURCE_LIST}"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"
rm -f "${OUTPUT_PATH}"
(
    cd "${CHAPTER_DIR}"
    zip -q -0 "${OUTPUT_PATH}" ./*.mp3
)

printf "Created Kobo audiobook: %s\n" "${OUTPUT_PATH}"

if [[ -n "${KOBO_MOUNT_PATH}" ]]; then
    cp "${OUTPUT_PATH}" "${KOBO_MOUNT_PATH}/"
    printf "Copied to Kobo: %s/%s\n" "${KOBO_MOUNT_PATH}" "$(basename "${OUTPUT_PATH}")"
    printf "Eject the Kobo, unplug it, then open My Books > Audiobooks.\n"
fi
