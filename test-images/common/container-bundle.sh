#!/bin/sh
set -e

ENGINE=
if command -V docker >/dev/null 2>&1; then
    ENGINE=docker
elif command -V podman >/dev/null 2>&1; then
    ENGINE=podman
    alias docker='podman'
fi

is_root() { [ "$(id -u)" = 0 ]; }

if ! is_root && command -V sudo >/dev/null 2>&1; then
    case "$ENGINE" in
        podman)
            alias docker='sudo podman'
            ;;
        docker)
            alias docker='sudo docker'
            ;;
    esac
else
    case "$ENGINE" in
        podman)
            alias docker='podman'
            ;;
    esac
fi


TEDGE_C8Y_URL="${TEDGE_C8Y_URL:-}"
DEVICE_ID="${DEVICE_ID:-}"

IMAGE_BASE="ghcr.io/thin-edge/tedge-container-bundle"
IMAGE="${IMAGE_BASE}:99.99.1"


# Build
build() {
    # Use labels to change the image hash
    # cd /build/
    for p in /build/*.tar.gz; do
        echo "Loading image from tarball: $p"
        docker load < "$p"
        echo
    done
}

prepare() {
    docker network create tedge ||:
    docker volume create device-certs ||:
    docker volume create tedge ||:
}

bootstrap_certificate() {
    docker run --rm \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        "$IMAGE" \
        tedge cert create --device-id "$DEVICE_ID"

    docker run --rm \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        -e "C8Y_USER=$C8Y_USER" \
        -e "C8Y_PASSWORD=$C8Y_PASSWORD" \
        "$IMAGE" \
        tedge cert upload c8y
}

start() {
    CONTAINER_OPTIONS=""

    # container engine specific instructions
    case "$ENGINE" in
        docker)
            CONTAINER_OPTIONS="$CONTAINER_OPTIONS --add-host host.docker.internal:host-gateway"
            CONTAINER_OPTIONS="$CONTAINER_OPTIONS -v /var/run/docker.sock:/var/run/docker.sock:rw"
            ;;
        podman)
            CONTAINER_OPTIONS="$CONTAINER_OPTIONS -v /var/run/docker.sock:/var/run/docker.sock:rw"
            ;;
    esac

    # shellcheck disable=SC2086
    docker run -d \
        --name tedge \
        $CONTAINER_OPTIONS \
        --restart always \
        --network tedge \
        -p "127.0.0.1:1883:1883" \
        -p "127.0.0.1:8000:8000" \
        -p "127.0.0.1:8001:8001" \
        -v "device-certs:/etc/tedge/device-certs" \
        -v "tedge:/data/tedge" \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        "$IMAGE"
}

ACTION="$1"

case "$ACTION" in
    start)
        build
        prepare
        bootstrap_certificate || echo "Failed to upload certificate"
        start
        ;;

    stop)
        echo "---------------- tedge container logs --------------------------"
        docker logs -n 1000 tedge 2>&1 ||:
        echo "----------------------------------------------------------------"

        echo
        echo "---------------- tedge workflow logs --------------------------"
        docker exec -t tedge sh -c 'head -n 10000 /data/tedge/logs/agent/*' ||:
        echo "----------------------------------------------------------------"

        docker container stop tedge ||:
        docker container rm tedge ||:
        ;;
esac
