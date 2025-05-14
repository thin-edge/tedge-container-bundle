#!/bin/sh
set -e

#
# Argument parsing
#
BUILD_DIR=${BUILD_DIR:-/build}
TEDGE_C8Y_URL="${TEDGE_C8Y_URL:-$C8Y_BASEURL}"
DEVICE_ID="${DEVICE_ID:-}"
IMAGE="ghcr.io/thin-edge/tedge-container-bundle:99.99.1"
CONTAINER_NAME=${CONTAINER_NAME:-"tedge"}
DEBUG=${DEBUG:-0}
CA=${CA:-c8y}
DEVICE_ONE_TIME_PASSWORD=${DEVICE_ONE_TIME_PASSWORD:-}

ACTION="$1"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --name)
            CONTAINER_NAME="$2"
            shift
            ;;
        --device-id)
            DEVICE_ID="$2"
            shift
            ;;
        --ca)
            CA="$2"
            shift
            ;;
        --c8y-url)
            TEDGE_C8Y_URL="$2"
            shift
            ;;
        --one-time-password|-p)
            DEVICE_ONE_TIME_PASSWORD="$2"
            shift
            ;;
        --load-image-dir)
            BUILD_DIR="$2"
            shift
            ;;
        --image)
            if [ -n "$2" ]; then
                IMAGE="$2"
            fi
            shift
            ;;
        --debug)
            DEBUG=1
            ;;
        --*|-*)
            echo "Unknown flag. $1" >&2
            exit 1
            ;;
        *)
            echo "Unknown argument. $1" >&2
            exit 1
            ;;
    esac
    shift
done

# Set default
if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID="tedge_$(date +%s)"
fi

TEDGE_C8Y_URL=$(echo "$TEDGE_C8Y_URL" | sed 's|^https://||' | sed 's|^https://||')

#
# Detect container engine
# and set an alias to docker to simplify the script
#
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
            if ! podman ps >/dev/null 2>&1; then
                docker() { sudo podman "$@"; }
            fi
            ;;
        docker)
            if ! docker ps >/dev/null 2>&1; then
                alias docker='sudo docker'
            fi
            ;;
    esac
else
    case "$ENGINE" in
        podman)
            alias docker='podman'
            ;;
    esac
fi

check_engine() {
    #
    # Wait until the container engine is ready
    #
    attempts=10
    while [ "$attempts" -gt 0 ]; do
        if docker ps >/dev/null 2>&1; then
            break
        fi
        echo "container engine is not yet ready. trying again in 5s" >&2
        attempts=$((attempts - 1))
        sleep 5
    done
}

# Build
build() {
    # Use labels to change the image hash
    if [ -d "$BUILD_DIR" ]; then
        for p in "$BUILD_DIR"/*.tar.gz; do
            echo "Loading image from tarball: $p"
            docker load < "$p"
            echo
        done
    fi
}

prepare() {
    docker network create tedge ||:
    docker volume create device-certs ||:
    docker volume create tedge ||:
}

bootstrap_certificate() {
    # Don't fail if the certificate already exits
    # as the script could of partially completed, and it should
    # still work when called again
    docker run --rm \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        "$IMAGE" \
        sh -c "tedge cert show 2>/dev/null || tedge cert create --device-id '$DEVICE_ID'"

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
            # Mount socket to a path expected by the container under test
            # In podman, host.containers.internal is accessible by default
            if [ -e /run/podman/podman.sock ]; then
                CONTAINER_OPTIONS="$CONTAINER_OPTIONS -v /run/podman/podman.sock:/var/run/docker.sock:rw"
            else
                echo "Could not the podman socket"
                exit 1
            fi
            ;;
    esac

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 ||:

    # shellcheck disable=SC2086
    docker run -d \
        --name "$CONTAINER_NAME" \
        $CONTAINER_OPTIONS \
        --restart always \
        --network tedge \
        -p "127.0.0.1:1883:1883" \
        -p "127.0.0.1:8000:8000" \
        -p "127.0.0.1:8001:8001" \
        -v "device-certs:/etc/tedge/device-certs" \
        -v "tedge:/data/tedge" \
        -e DEVICE_ID="$DEVICE_ID" \
        -e CA="$CA" \
        -e DEVICE_ONE_TIME_PASSWORD="$DEVICE_ONE_TIME_PASSWORD" \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        "$IMAGE"

    sleep 5

    if [ "$DEBUG" = 1 ]; then
        # Show logs (to help with debugging when something unexpected happens)
        echo "------ container startup logs ------"
        docker logs --tail 1000 tedge 2>&1
        echo "------------------------------------"
    fi
}

stop() {
    if [ "$DEBUG" = 1 ]; then
        echo "---------------- tedge container logs --------------------------"
        docker logs --tail 1000 tedge 2>&1 ||:
        echo "----------------------------------------------------------------"

        echo
        echo "---------------- tedge workflow logs --------------------------"
        docker exec -t tedge sh -c 'head -n 10000 /data/tedge/logs/agent/*' ||:
        echo "----------------------------------------------------------------"
    fi
    docker container stop tedge >/dev/null ||:
    docker container rm tedge >/dev/null ||:
}

delete_resources() {
    docker volume rm tedge >/dev/null ||:
    docker volume rm device-certs >/dev/null ||:
}

#
# Main
#
case "$ACTION" in
    start)
        check_engine
        build
        prepare
        if [ "$CA" = "self-signed" ]; then
            bootstrap_certificate
        fi
        start
        ;;
    stop)
        stop
        ;;
    delete)
        stop
        delete_resources
        ;;
esac
