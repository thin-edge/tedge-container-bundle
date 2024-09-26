#!/bin/sh
set -e

OK=0
FAILED=1

if [ "$DEBUG" = 1 ]; then
    set -x
fi

# TODOs
# * Allow updating to an explicit image (don't always assume it is staying the same)
#   * Allow flags to set the target image and tag (so don't read it from the image)

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
        exit "$OK"
    fi

    if [ "$CURRENT_IMAGE" = "$TARGET_IMAGE" ]; then
        echo "Container image is already up to date"
        return "$FAILED"
    fi
    echo "New image is available. old=$CURRENT_IMAGE, new=$TARGET_IMAGE"
    return "$OK"
}

is_container_running() {
    IS_RUNNING=$($DOCKER_CMD inspect "$1" --format "{{.State.Running}}" 2>/dev/null ||:)
    [ "$IS_RUNNING" = true ]
}

wait_for_stop() {
    attempt=1
    while [ "$attempt" -le 90 ]; do
        if ! is_container_running "$CURRENT_CONTAINER_ID"; then
            return "$OK"
        fi
        attempt=$((attempt+1))
        sleep 1
    done
    return "$FAILED"
}

update() {
    echo "Removing existing container. name=$CONTAINER_NAME, id=$CURRENT_CONTAINER_ID"

    # TODO: Wait for the container to stop (this is the hand-off)
    if ! wait_for_stop; then
        echo "Container was not shutdown. Aborting update"
        exit "$FAILED"
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
    # Check container state
    IS_RUNNING=$($DOCKER_CMD inspect "$NEXT_CONTAINER_ID" --format "{{.State.Running}}" 2>/dev/null ||:)
    if [ "$IS_RUNNING" != true ]; then
        return "$FAILED"
    fi

    # Check cloud connectivity
    if $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge config get c8y.url; then
        if ! $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge connect c8y --test; then
            return "$FAILED"
        fi
    fi

    if $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge config get aws.url; then
        if ! $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge connect aws --test; then
            return "$FAILED"
        fi
    fi

    if $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge config get az.url; then
        if ! $DOCKER_CMD exec -t "$NEXT_CONTAINER_ID" tedge connect az --test; then
            return "$FAILED"
        fi
    fi

    CONTAINER_IMAGE=$($DOCKER_CMD inspect "$NEXT_CONTAINER_ID" --format "{{.Image}}")
    echo "New image: $CONTAINER_IMAGE"

    return "$OK"
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

publish_message() {
    topic_suffix="$1"
    payload="$2"
    shift
    shift
    TOPIC_ROOT=$(tedge config get mqtt.topic_root ||:)
    TOPIC_ID=$(tedge config get mqtt.device_topic_id ||:)
    if ! tedge mqtt pub -q 1 "$TOPIC_ROOT/$TOPIC_ID/$topic_suffix" "$payload" "$@"; then
        echo "Warning: Failed to publish MQTT message" >&2
    fi
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
        exit "$FAILED"
    fi

    if [ -n "$TEDGE_VERSION" ]; then
        PAYLOAD=$(printf '{"text":"%s"}' "Updating thin-edge.io from $TEDGE_VERSION")
        publish_message "e/tedge_self_update" "$PAYLOAD"
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
            exit "$OK"
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
            exit "$OK"
        fi
        # Image is already up to date
        exit "$FAILED"
        ;;
    verify)
        # TODO: Collect logs from the updater container and then delete it
        # to enable easier debugging
        prepare
        if needs_update; then
            # Update is still not up to date
            exit "$FAILED"
        fi

        # Image is already up to date
        PAYLOAD=$(printf '{"text":"%s"}' "Successfully updated thin-edge.io to $TEDGE_VERSION")
        publish_message "e/tedge_self_update" "$PAYLOAD"
        exit "$OK"
        ;;
    update_background)
        prepare
        if ! needs_update; then
            exit "$OK"
        fi
        update_background
        ;;
    update)
        prepare
        if ! needs_update; then
            exit "$OK"
        fi
        if ! update; then
            rollback
            exit "$OK"
        fi

        if ! healthcheck; then
            rollback
        fi
        ;;
    *)
        echo "Unknown command. $ACTION" >&2
        usage
        exit "$FAILED"
        ;;
esac

