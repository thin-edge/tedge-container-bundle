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

DOCKER_CMD=docker
if ! docker ps >/dev/null 2>&1; then
    if command -V sudo >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi
fi

CONTAINER_NAME=${CONTAINER_NAME:-}
if [ -z "$CONTAINER_NAME" ]; then
    # Use the name of the container rather than the hostname as it human friendly
    # and strip any leading slash (/)
    CONTAINER_NAME=$($DOCKER_CMD inspect "$(hostname)" --format "{{.Name}}" | sed 's|^/||g')
fi

TMP_LOG_DIR=$(mktemp -d)
# Ensure directory is always deleted afterwards
trap 'rm -rf -- "$TMP_LOG_DIR"' EXIT
TMP_FILE="${TMP_LOG_DIR}/${TYPE}_${CONTAINER_NAME}_$(date -Iseconds).log"

# Add log header to give information about the contents
{
    echo "---------------- log parameters ----------------------"
    echo "container:  $CONTAINER_NAME"
    echo "dateFrom:   $DATE_FROM"
    echo "dateTo:     $DATE_TO"
    echo "maxLines:   $MAX_LINES"
    echo "command:    $DOCKER_CMD logs -n \"$MAX_LINES\" --since \"$DATE_FROM\" --until \"$DATE_TO\" \"$CONTAINER_NAME\""
    echo "------------------------------------------------------"
    echo
} > "$TMP_FILE"

# Write logs to file (stripping any ansci colour codes)
$DOCKER_CMD logs -n "$MAX_LINES" --since "$DATE_FROM" --until "$DATE_TO" "$CONTAINER_NAME" \
    | sed -e 's/\x1b\[[0-9;]*m//g' \
    | tee -a "$TMP_FILE"

echo "Uploading log file to $UPLOAD_URL" >&2

# Use mtls if configured
if [ -f "$(tedge config get http.client.auth.key_file)" ] && [ -f "$(tedge config get http.client.auth.cert_file)" ]; then
    # Upload using mtl
    echo "Uploading log file using mtls"
    curl -4 -sf \
        -XPUT \
        --data-binary "@$TMP_FILE" \
        --capath "$(tedge config get http.ca_path)" \
        --key "$(tedge config get http.client.auth.key_file)" \
        --cert "$(tedge config get http.client.auth.cert_file)" \
        "$UPLOAD_URL"
else
    # Upload using default
    curl -4 -sf -XPUT --data-binary "@$TMP_FILE" "$UPLOAD_URL"
fi
