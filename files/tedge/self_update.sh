#!/bin/sh
set -e

if [ "$DEBUG" = 1 ]; then
    set -x
fi

usage() {
    cat << EOT
$0 needs_update     - Check if the container image is up to date. exit=0 means an update is necessary
$0 update           - Update the container (but also still perform an image check)
$0 update_background - Trigger a container upgrade in the background independent of the script

Trigger a self update of a container with a given container name
EOT
}

TAG="${TAG:-latest}"
# IMAGE_NAME="ghcr.io/thin-edge/tedge-container-bundle:${TAG}"
IMAGE_NAME="tedge-container-bundle"
NETWORK_MODE=tedge

CONTAINER_NAME="${CONTAINER_NAME:-tedge}"
TEDGE_C8Y_URL="${TEDGE_C8Y_URL:-}"
CURRENT_IMAGE=
TARGET_IMAGE=
IGNORE_IMAGE_CHECK=0

DOCKER_CMD=docker
if ! docker ps >/dev/null 2>&1; then
    if command -V sudo >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi
fi

prepare() {
    echo "Preparing for updating container with name=$CONTAINER_NAME"
    # Use container id to prevent any unexpected changes
    CURRENT_CONTAINER_ID=$($DOCKER_CMD inspect "$CONTAINER_NAME" --format "{{.Id}}" ||:)

    name=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Config.Image}}" ||:)
    if [ -n "$name" ]; then
        IMAGE_NAME="$name"
    fi

    # Get required parameters from container before stopping it
    value=$($DOCKER_CMD exec "$CURRENT_CONTAINER_ID" tedge config get c8y.url ||:)
    if [ -n "$value" ]; then
        TEDGE_C8Y_URL="$value"
    fi

    value=$($DOCKER_CMD inspect tedge --format "{{.HostConfig.NetworkMode}}" ||:)
    if [ -n "$value" ]; then
        NETWORK_MODE="$value"
    fi
}

needs_update() {
    CURRENT_IMAGE=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Image}}" ||:)
    echo "Current image: $CURRENT_IMAGE"

    case "${1:-}" in
        pull)
            echo "Pulling new image: ${IMAGE_NAME}"
            $DOCKER_CMD pull "$IMAGE_NAME" >/dev/null ||:
            ;;
    esac

    TARGET_IMAGE=$($DOCKER_CMD image inspect "$IMAGE_NAME" --format "{{.Id}}")

    if [ "$IGNORE_IMAGE_CHECK" = 1 ]; then
        echo "Forcing a container update"
        exit 0
    fi

    if [ "$CURRENT_IMAGE" = "$TARGET_IMAGE" ]; then
        echo "Container image is already up to date"
        return 1
    fi
    echo "New image is available. old=$CURRENT_IMAGE, new=$TARGET_IMAGE"
    return 0
}

is_container_running() {
    IS_RUNNING=$($DOCKER_CMD inspect "$1" --format "{{.State.Running}}" 2>/dev/null ||:)
    [ "$IS_RUNNING" = true ]
}

wait_for_stop() {
    attempt=1
    while [ "$attempt" -le 90 ]; do
        if ! is_container_running "$CURRENT_CONTAINER_ID"; then
            return 0
        fi
        attempt=$((attempt+1))
        sleep 1
    done
    return 1
}

update() {
    echo "Removing existing container. name=$CONTAINER_NAME, id=$CURRENT_CONTAINER_ID"

    # TODO: Wait for the container to stop (this is the hand-off)
    if ! wait_for_stop; then
        echo "Container was not shutdown. Aborting update"
        exit 1
    fi

    # Make sure the container is stopped and not in the process of restarting
    $DOCKER_CMD stop --time 90 "$CURRENT_CONTAINER_ID" ||:

    # remove any existing backup-name
    $DOCKER_CMD rm "${CONTAINER_NAME}-bak" ||:
    $DOCKER_CMD container rename "$CURRENT_CONTAINER_ID" "${CONTAINER_NAME}-bak"

    echo "Starting the tedge container. name=$CONTAINER_NAME"
    NEXT_CONTAINER_ID=$(
        $DOCKER_CMD run -d \
            --name "$CONTAINER_NAME" \
            --restart=always \
            --network "$NETWORK_MODE" \
            -v "device-certs:/etc/tedge/device-certs" \
            -v "mosquitto:/mosquitto/data" \
            -v /var/run/docker.sock:/var/run/docker.sock:rw \
            -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
            "$IMAGE_NAME"
    )
}

is_functional() {
    # TODO: How thorough should this check be? Doing a connectivity check?
    IS_RUNNING=$($DOCKER_CMD inspect "$NEXT_CONTAINER_ID" --format "{{.State.Running}}" 2>/dev/null ||:)
    if [ "$IS_RUNNING" != true ]; then
        return 1
    fi

    # FIXME: tedge command to check that all cloud connections are functional?
    if $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge config get c8y.url; then
        if ! $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge connect c8y --test; then
            return 1
        fi
    fi

    CONTAINER_IMAGE=$($DOCKER_CMD inspect "$NEXT_CONTAINER_ID" --format "{{.Image}}")
    echo "New image: $CONTAINER_IMAGE"

    # OK
    return 0
}

healthcheck() {
    echo "Checking new container's health"
    sleep 2
    ATTEMPT=1
    TIMED_OUT=0
    while :; do
        if [ "$ATTEMPT" -gt 10 ]; then
            TIMED_OUT=1
            break
        fi
        if is_functional; then
            echo "Container is working"
            break
        fi
        ATTEMPT=$((ATTEMPT+1))
        sleep 1
    done

    return "$TIMED_OUT"
}

rollback() {
    $DOCKER_CMD stop "$NEXT_CONTAINER_ID" ||:
    $DOCKER_CMD rm "$NEXT_CONTAINER_ID" ||:

    $DOCKER_CMD container rename "$CURRENT_CONTAINER_ID" "${CONTAINER_NAME}"
    $DOCKER_CMD container update "$CURRENT_CONTAINER_ID" --restart always
    $DOCKER_CMD start "$CURRENT_CONTAINER_ID" ||:
}

update_background() {
    echo "Starting background container to perform the container update"
    UPDATER_CONTAINER_ID=$(
        $DOCKER_CMD run -d \
            -v /var/run/docker.sock:/var/run/docker.sock:rw \
            "$IMAGE_NAME" \
            "$0" update
    )
    echo "Update container id: $UPDATER_CONTAINER_ID"

    # Set the container to restart (but only after the background service was launched successfully)
    echo "Setting restart policy to no for existing container"
    $DOCKER_CMD container update "${CURRENT_CONTAINER_ID}" --restart no

    # wait for service to start and be stable
    sleep 5

    if ! is_container_running "$UPDATER_CONTAINER_ID"; then
        echo "Container updater crashed. id=$UPDATER_CONTAINER_ID"
        exit 1
    fi

    if [ -n "$TEDGE_VERSION" ]; then
        TOPIC_ROOT=$(tedge config get mqtt.topic_root ||:)
        TOPIC_ID=$(tedge config get mqtt.device_topic_id ||:)
        PAYLOAD=$(printf '{"text":"%s"}' "Updating thin-edge.io from $TEDGE_VERSION")
        tedge mqtt pub -q 1 "$TOPIC_ROOT/$TOPIC_ID/e/tedge_self_update" "$PAYLOAD" ||:
    fi

    # Give some time for the message to be published
    sleep 5

    # Wait for the process to be killed by the background updater
    # sleep 90
    # exit 1
}

#
# Argument parsing
#
ACTION=

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --*|-*)
            ;;
        *)
            ACTION="$1"
            ;;
    esac
    shift
done

#
# Main
#
# TODO: Or should the version be read from the container image instead (that would be more generic)
TEDGE_VERSION=
if command -V tedge >/dev/null 2>&1; then
    TEDGE_VERSION=$(tedge --version | rev | cut -d ' ' -f1 | rev)
fi

case "$ACTION" in
    needs_update)
        prepare
        if needs_update pull; then
            printf ':::begin-tedge:::\n{"tedgeVersion":"%s"}\n:::end-tedge:::\n' "$TEDGE_VERSION"
            exit 0
        fi
        # Image is already up to date
        exit 1
        ;;
    update_background)
        prepare
        if ! needs_update; then
            exit 0
        fi
        update_background
        ;;
    update)
        prepare
        if ! needs_update; then
            exit 0
        fi
        if ! update; then
            rollback
            exit 0;
        fi

        if ! healthcheck; then
            rollback
        fi
        ;;
    verify)
        # TODO: Collect logs from the updater container and then delete it
        # to enable easier debugging
        ;;
    *)
        echo "Unknown command. $ACTION" >&2
        usage
        exit 1
        ;;
esac

