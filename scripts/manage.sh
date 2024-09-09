#!/usr/bin/env bash
set -e
DOTENV=".env"

# Only use interactive/tty when it is available
DOCKER_OPTIONS=""
if [ -t 1 ]; then
    DOCKER_OPTIONS="-it"
fi

set -a
# shellcheck disable=SC1090
source "$DOTENV"
set +a

if [ -n "$CI" ]; then
    set -x
fi

DEVICE_CERTS="$(pwd)/device-certs"
mkdir -p "$DEVICE_CERTS"

show_common_name() {
    docker run $DOCKER_OPTIONS -v "$DEVICE_CERTS:/etc/tedge/device-certs" ghcr.io/thin-edge/tedge:latest tedge config get device.id | sed 's/\r$//g'
}

create_cert() {
    COMMON_NAME="$1"
    if command -V tedge >/dev/null 2>&1; then
        tedge cert create --config-dir "$(pwd)" --device-id "$COMMON_NAME"
    else
        docker run $DOCKER_OPTIONS --user "$UID:$GID" -v "$DEVICE_CERTS:/etc/tedge/device-certs" ghcr.io/thin-edge/tedge:latest tedge cert create --device-id "$COMMON_NAME"
    fi
    chmod 444 "$DEVICE_CERTS"/*
}

upload() {
    COMMON_NAME=$(show_common_name)
    if [ -z "$COMMON_NAME" ]; then
        echo "Could not detect certificate common name" >&2
        exit 1
    fi
    if [ ! -f "$DEVICE_CERTS/tedge-certificate.pem" ]; then
        echo "device certificate does not exist: $DEVICE_CERTS/tedge-certificate.pem" >&2
        exit 1
    fi

    c8y devicemanagement certificates create \
        -n \
        --name "$COMMON_NAME" \
        --file "$DEVICE_CERTS/tedge-certificate.pem" \
        --autoRegistrationEnabled \
        --status ENABLED \
        --silentStatusCodes 409 \
        --silentExit
}

main() {
    ACTION="$1"
    shift
    case "$ACTION" in
        init)
            DEVICE_ID=${DEVICE_ID:-$1}
            if [ -z "$DEVICE_ID" ]; then
                echo "Missing required argument or DEVICE_ID env variable. COMMON_NAME" >&2
                exit 1
            fi
            mkdir -p "$DEVICE_CERTS"
            create_cert "$DEVICE_ID"
            ;;
        delete)
            echo "Removing device certificates: $DEVICE_CERTS"
            rm -rf "$DEVICE_CERTS"
            ;;
        upload)
            upload
            ;;
        show)
            show_common_name
            ;;
    esac
}

main "$@"
