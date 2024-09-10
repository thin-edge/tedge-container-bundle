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

VOLUME=${VOLUME:-device-certs}

show() {
    value=$(
        docker run -t=false -i=false -v "$VOLUME:/etc/tedge/device-certs" ghcr.io/thin-edge/tedge:latest tedge config get device.id     
    )
    echo -n "$value"
}

create_cert() {
    NAME="$1"
    docker volume create "$VOLUME"
    docker run $DOCKER_OPTIONS -v "$VOLUME:/etc/tedge/device-certs" ghcr.io/thin-edge/tedge:latest tedge cert create --device-id "$NAME"
}

upload() {
    docker run $DOCKER_OPTIONS \
        -v "$VOLUME:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL:-$C8Y_DOMAIN}" \
        -e "C8Y_USER=$C8Y_USER" \
        -e "C8Y_PASSWORD=$C8Y_PASSWORD" \
        ghcr.io/thin-edge/tedge:latest tedge cert upload c8y
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
            create_cert "$DEVICE_ID"
            ;;
        delete)
            echo "Removing device certificates: $VOLUME"
            docker volume rm "$VOLUME"
            ;;
        upload)
            upload
            ;;
        show)
            show
            ;;
    esac
}

main "$@"
