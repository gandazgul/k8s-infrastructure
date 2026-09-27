#!/bin/bash
set -e

ENV_FILE=".env.bookorbit"
KOBO_MOUNT_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            if [[ $# -lt 2 ]]; then
                printf "Missing value for --env\n"
                exit 1
            fi

            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            printf "Usage: %s [--env .env.bookorbit] [/path/to/kobo-mount]\n" "$0"
            printf "\n"
            printf "The script reads .env.bookorbit when it exists. Set these values there:\n"
            printf "  BOOKORBIT_KOBO_VOLUME=/Volumes/KOBOeReader\n"
            printf "  BOOKORBIT_URL=https://read.dumbhome.uk\n"
            printf "  BOOKORBIT_PLUGIN_ZIP=$HOME/Downloads/bookorbit-koreader-plugin.zip\n"
            printf "\n"
            printf "BOOKORBIT_PLUGIN_ZIP is the preconfigured KOReader plugin zip from BookOrbit Settings > KOReader.\n"
            printf "It includes the BookOrbit plugin plus the server and sync credentials.\n"
            printf "\n"
            exit 0
            ;;
        *)
            if [[ -n "${KOBO_MOUNT_ARG}" ]]; then
                printf "Unknown argument: %s\n" "$1"
                exit 1
            fi

            KOBO_MOUNT_ARG="$1"
            shift
            ;;
    esac
done

load_env_file() {
    if [[ ! -f "$1" ]]; then
        return
    fi

    while IFS= read -r ENV_LINE || [[ -n "${ENV_LINE}" ]]; do
        ENV_LINE="${ENV_LINE%$'\r'}"

        if [[ -z "${ENV_LINE}" || "${ENV_LINE}" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        ENV_LINE="${ENV_LINE#export }"

        if [[ ! "${ENV_LINE}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            printf "Invalid env line in %s: %s\n" "$1" "${ENV_LINE}"
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
    done < "$1"
}

load_env_file "${ENV_FILE}"

KOBO_MOUNT_PATH="${KOBO_MOUNT_ARG:-${KOBO_MOUNT_PATH:-${BOOKORBIT_KOBO_VOLUME:-}}}"
BOOKORBIT_PLUGIN_ZIP="${BOOKORBIT_PLUGIN_ZIP:-}"
BOOKORBIT_SERVER_URL="${BOOKORBIT_SERVER_URL:-${BOOKORBIT_URL:-https://read.dumbhome.uk}}"
BOOKORBIT_SERVER_URL="${BOOKORBIT_SERVER_URL%/}"

case "${BOOKORBIT_PLUGIN_ZIP}" in
    '~/'*)
        BOOKORBIT_PLUGIN_ZIP="${HOME}/${BOOKORBIT_PLUGIN_ZIP#~/}"
        ;;
    '$HOME/'*)
        BOOKORBIT_PLUGIN_ZIP="${HOME}/${BOOKORBIT_PLUGIN_ZIP#\$HOME/}"
        ;;
esac

if [[ -z "${KOBO_MOUNT_PATH}" ]]; then
    printf "Usage: %s [--env .env.bookorbit] [/path/to/kobo-mount]\n" "$0"
    printf "\n"
    printf "Set BOOKORBIT_KOBO_VOLUME in %s or pass the Kobo mount path as an argument.\n" "${ENV_FILE}"
    printf "Optional values in %s:\n" "${ENV_FILE}"
    printf "  BOOKORBIT_PLUGIN_ZIP=$HOME/Downloads/bookorbit-koreader-plugin.zip\n"
    printf "  BOOKORBIT_URL=https://read.dumbhome.uk\n"
    printf "\n"
    printf "BOOKORBIT_PLUGIN_ZIP is the preconfigured KOReader plugin zip from BookOrbit Settings > KOReader.\n"
    printf "It makes KOReader + BookOrbit work without entering server and sync credentials on the Kobo.\n"
    printf "\n"
    exit 1
fi

if [[ ! -d "${KOBO_MOUNT_PATH}" ]]; then
    printf "Kobo mount path does not exist: %s\n" "${KOBO_MOUNT_PATH}"
    exit 1
fi

if [[ ! -d "${KOBO_MOUNT_PATH}/.kobo" ]]; then
    printf "This does not look like a mounted Kobo volume: %s\n" "${KOBO_MOUNT_PATH}"
    printf "Missing directory: %s/.kobo\n" "${KOBO_MOUNT_PATH}"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    printf "curl is required. Install curl and run again.\n"
    exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
    printf "unzip is required. Install unzip and run again.\n"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf "python3 is required. Install python3 and run again.\n"
    exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

printf "Installing NickelMenu launcher update on the Kobo.\n"
curl --fail --location --silent --show-error \
    "https://github.com/pgaskin/NickelMenu/releases/latest/download/KoboRoot.tgz" \
    --output "${KOBO_MOUNT_PATH}/.kobo/KoboRoot.tgz"

printf "Finding latest KOReader Kobo release.\n"
KOREADER_RELEASE_URL="$(curl --fail --location --silent --show-error --output /dev/null --write-out '%{url_effective}' \
    "https://github.com/koreader/koreader/releases/latest")"
KOREADER_TAG="${KOREADER_RELEASE_URL##*/}"
KOREADER_ZIP_URL="https://github.com/koreader/koreader/releases/download/${KOREADER_TAG}/koreader-kobo-${KOREADER_TAG}.zip"
KOREADER_ZIP="${WORK_DIR}/koreader-kobo.zip"

printf "Downloading KOReader from %s\n" "${KOREADER_ZIP_URL}"
curl --fail --location --silent --show-error "${KOREADER_ZIP_URL}" --output "${KOREADER_ZIP}"

printf "Copying KOReader to .adds/koreader.\n"
unzip -q "${KOREADER_ZIP}" -d "${WORK_DIR}/koreader"
mkdir -p "${KOBO_MOUNT_PATH}/.adds"
cp -R "${WORK_DIR}/koreader/koreader" "${KOBO_MOUNT_PATH}/.adds/"

printf "Adding KOReader NickelMenu entry.\n"
mkdir -p "${KOBO_MOUNT_PATH}/.adds/nm"
printf "menu_item:main:KOReader:cmd_spawn:quiet:exec /mnt/onboard/.adds/koreader/koreader.sh\n" \
    > "${KOBO_MOUNT_PATH}/.adds/nm/koreader"

printf "Preventing Nickel from indexing KOReader hidden folders.\n"
python3 - "${KOBO_MOUNT_PATH}/.kobo/Kobo/Kobo eReader.conf" <<'PY'
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
exclude_value = r"ExcludeSyncFolders=(\.(?!kobo|adobe).+|([^.][^/]*/)+\..+)"

if config_path.exists():
    lines = config_path.read_text(encoding="utf-8").splitlines()
else:
    lines = []

output = []
in_feature_settings = False
feature_settings_seen = False
exclude_written = False

for line in lines:
    stripped = line.strip()

    if stripped.startswith("[") and stripped.endswith("]"):
        if in_feature_settings and not exclude_written:
            output.append(exclude_value)
            exclude_written = True
        in_feature_settings = stripped == "[FeatureSettings]"
        feature_settings_seen = feature_settings_seen or in_feature_settings
        output.append(line)
        continue

    if in_feature_settings and stripped.startswith("ExcludeSyncFolders="):
        if not exclude_written:
            output.append(exclude_value)
            exclude_written = True
        continue

    output.append(line)

if not feature_settings_seen:
    if output and output[-1] != "":
        output.append("")
    output.append("[FeatureSettings]")
    output.append(exclude_value)
elif in_feature_settings and not exclude_written:
    output.append(exclude_value)

config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text("\n".join(output) + "\n", encoding="utf-8")
PY

printf "Installing BookOrbit KOReader plugin.\n"
mkdir -p "${KOBO_MOUNT_PATH}/.adds/koreader/plugins"

if [[ -n "${BOOKORBIT_PLUGIN_ZIP}" ]]; then
    if [[ ! -f "${BOOKORBIT_PLUGIN_ZIP}" ]]; then
        printf "BookOrbit plugin zip does not exist: %s\n" "${BOOKORBIT_PLUGIN_ZIP}"
        exit 1
    fi

    unzip -q "${BOOKORBIT_PLUGIN_ZIP}" -d "${WORK_DIR}/bookorbit-plugin"
else
    curl --fail --location --silent --show-error \
        "https://github.com/bookorbit/bookorbit/archive/refs/heads/main.zip" \
        --output "${WORK_DIR}/bookorbit.zip"
    unzip -q "${WORK_DIR}/bookorbit.zip" -d "${WORK_DIR}/bookorbit-plugin"
fi

BOOKORBIT_PLUGIN_DIR="$(find "${WORK_DIR}/bookorbit-plugin" -type d -name 'bookorbit.koplugin' | head -n 1)"

if [[ -z "${BOOKORBIT_PLUGIN_DIR}" ]]; then
    printf "Could not find bookorbit.koplugin in the plugin archive.\n"
    exit 1
fi

rm -rf "${KOBO_MOUNT_PATH}/.adds/koreader/plugins/bookorbit.koplugin"
cp -R "${BOOKORBIT_PLUGIN_DIR}" "${KOBO_MOUNT_PATH}/.adds/koreader/plugins/"

printf "\nDone. Eject the Kobo, unplug it, and let it process the NickelMenu update.\n"
if [[ -n "${BOOKORBIT_PLUGIN_ZIP}" ]]; then
    printf "Installed the preconfigured BookOrbit plugin zip: %s\n" "${BOOKORBIT_PLUGIN_ZIP}"
    printf "KOReader should use the embedded BookOrbit server and sync credentials.\n"
else
    printf "After KOReader starts, open Tools > BookOrbit and use server: %s\n" "${BOOKORBIT_SERVER_URL}"
    printf "For automatic setup, set BOOKORBIT_PLUGIN_ZIP in %s to the preconfigured plugin zip from BookOrbit Settings > KOReader.\n" "${ENV_FILE}"
fi
