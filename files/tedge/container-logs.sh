#!/bin/sh
set -e

CONTAINER_NAME=
DATE_FROM=${DATE_FROM:-"24h"}
DATE_TO=${DATE_TO:-"0m"}
MAX_LINES=${MAX_LINES:-1000}
UPLOAD_URL=
TYPE=${TYPE:-container}

while [ $# -gt 0 ]; do
    case "$1" in
        --container)
            CONTAINER_NAME="$2"
            shift
            ;;
        --type)
            TYPE="$2"
            shift
            ;;
        --since)
            DATE_FROM="$2"
            shift
            ;;
        --until)
            DATE_TO="$2"
            shift
            ;;
        --max-lines|-n)
            MAX_LINES="$2"
            shift
            ;;
        --url)
            UPLOAD_URL="$2"
            shift
            ;;
        --help|-h)
            ;;
        *)
            ;;
    esac
    shift
done

SUDO=
if command -V sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi
LOGS_CMD="$SUDO tedge-container tools container-logs"

CONTAINER_NAME=${CONTAINER_NAME:-}

if [ -z "$CONTAINER_NAME" ]; then
    # Lookup current container name so it can be included in the log header (though technically it isn't needed)
    CONTAINER_NAME=$($SUDO tedge-container self list 2>/dev/null | head -n1 | cut -f1)
fi

TMP_LOG_DIR=$(mktemp -d)
# Ensure directory is always deleted afterwards
trap 'rm -rf -- "$TMP_LOG_DIR"' EXIT
TMP_FILE="${TMP_LOG_DIR}/${TYPE}_${CONTAINER_NAME}_$(date +%Y-%m-%dT%H:%M:%S%z).log"

# Add log header to give information about the contents
{
    echo "---------------- log parameters ----------------------"
    echo "container:  ${CONTAINER_NAME:-current_container}"
    echo "dateFrom:   $DATE_FROM"
    echo "dateTo:     $DATE_TO"
    echo "maxLines:   $MAX_LINES"
    echo "command:    $LOGS_CMD --tail \"$MAX_LINES\" --since \"$DATE_FROM\" --until \"$DATE_TO\" \"$CONTAINER_NAME\""
    echo "------------------------------------------------------"
    echo
} > "$TMP_FILE"

# Write logs to file (stripping any ansi codes)
# Since we're in posix shell, we can't use -o pipefail, so instead we have to
# use a marker file which exists when an error was encountered as outlined here: https://www.shellcheck.net/wiki/SC3040
LOG_FAILED="$TMP_LOG_DIR/failed"
# shellcheck disable=SC2086
{ $LOGS_CMD --tail "$MAX_LINES" --since "$DATE_FROM" --until "$DATE_TO" $CONTAINER_NAME 2>&1 || echo > "$LOG_FAILED"; } \
    | sed -e 's/\x1b\[[0-9;]*m//g' \
    | tee -a "$TMP_FILE"

if [ -f "$LOG_FAILED" ]; then
    echo "Failed to get container logs" >&2
    exit 1
fi

echo "Uploading log file to $UPLOAD_URL" >&2

# Use mtls if configured
if [ -f "$(tedge config get http.client.auth.key_file)" ] && [ -f "$(tedge config get http.client.auth.cert_file)" ]; then
    # Upload using mtl
    echo "Uploading log file using mtls"
    curl -4 -sfL \
        -XPUT \
        --data-binary "@$TMP_FILE" \
        --capath "$(tedge config get http.ca_path)" \
        --key "$(tedge config get http.client.auth.key_file)" \
        --cert "$(tedge config get http.client.auth.cert_file)" \
        "$UPLOAD_URL"
else
    # Upload using default
    curl -4 -sfL -XPUT --data-binary "@$TMP_FILE" "$UPLOAD_URL"
fi
