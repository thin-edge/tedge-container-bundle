#!/bin/sh
set -e

OK=0
FAILED=1

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

IMAGE="${IMAGE:-}"
NETWORK_MODE=${NETWORK_MODE:-tedge}

CONTAINER_NAME="${CONTAINER_NAME:-tedge}"
TEDGE_C8Y_URL="${TEDGE_C8Y_URL:-}"
CURRENT_IMAGE_ID=
TARGET_IMAGE_ID=
FORCE=0

# Internal
CURRENT_CONTAINER_ID=
CURRENT_CONTAINER_CONFIG_IMAGE=

DOCKER_CMD=docker
if ! docker ps >/dev/null 2>&1; then
    if command -V sudo >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi
fi

log() {
    echo "INFO $*" >&2
}

prepare() {
    log "Preparing for updating container. name=$CONTAINER_NAME"
    # Use container id to prevent any unexpected changes
    CURRENT_CONTAINER_ID=$($DOCKER_CMD inspect "$CONTAINER_NAME" --format "{{.Id}}" ||:)
    CURRENT_CONTAINER_CONFIG_IMAGE=$($DOCKER_CMD inspect "$CONTAINER_NAME" --format "{{.Config.Image}}" ||:)

    if [ -z "$IMAGE" ]; then
        value=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Config.Image}}" ||:)
        if [ -n "$value" ]; then
            IMAGE="$value"
            log "Detected container image from container. id=$CURRENT_CONTAINER_ID, image=$value"
        fi
    fi

    # Get required parameters from the existing container
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
    CURRENT_IMAGE_ID=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Image}}" ||:)
    CURRENT_IMAGE_NAME=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Config.Image}}" ||:)
    log "Current container. imageId=$CURRENT_IMAGE_ID, imageName=$CURRENT_IMAGE_NAME"

    case "${1:-}" in
        pull)
            log "Pulling new image: ${IMAGE}"
            $DOCKER_CMD pull "$IMAGE" >/dev/null ||:
            ;;
    esac

    TARGET_IMAGE_ID=$($DOCKER_CMD image inspect "$IMAGE" --format "{{.Id}}")

    if [ "$FORCE" = 1 ]; then
        log "Forcing a container update"
        return "$OK"
    fi

    # TODO: Also check if the image name has changed
    # IMAGE_NAME_MATCHES=0    
    # TARGET_IMAGE_TAGS=$(docker image inspect tedge-container-bundle-tedge-next --format '{{.RepoTags | json}}' | jq -r '. | @tsv')
    # for tag in $TARGET_IMAGE_TAGS; do
    #     if [ "$tag" = "$CURRENT_IMAGE_NAME" ]; then
    #         IMAGE_NAME_MATCHES=1
    #         break
    #     fi
    # done

    if [ "$CURRENT_IMAGE_ID" = "$TARGET_IMAGE_ID" ]; then
        # Note: Treat an image name/tag change the same as a new image
        # as the user may want to rename the container to be more descriptive
        if [ "$CURRENT_IMAGE_NAME" = "$IMAGE" ]; then
            log "Container image is already up to date"
            return "$FAILED"
        else
            log "Image id is the same, however the image name has changed. old=$CURRENT_IMAGE_NAME, new=$IMAGE"
        fi
    fi

    log "New image is available. old=$CURRENT_IMAGE_NAME ($CURRENT_IMAGE_ID), new=$IMAGE ($TARGET_IMAGE_ID)"
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
    log "Removing existing container. name=$CONTAINER_NAME, id=$CURRENT_CONTAINER_ID"

    # TODO: Wait for the container to stop (this is the hand-off)
    if ! wait_for_stop; then
        log "Container was not shutdown. Aborting update"
        exit "$FAILED"
    fi

    # Make sure the container is stopped and not in the process of restarting
    $DOCKER_CMD stop --time 90 "$CURRENT_CONTAINER_ID" ||:

    # remove any existing backup-name
    $DOCKER_CMD rm "${CONTAINER_NAME}-bak" ||:
    $DOCKER_CMD container rename "$CURRENT_CONTAINER_ID" "${CONTAINER_NAME}-bak"

    log "Starting the tedge container. name=$CONTAINER_NAME"
    # FIXME: How to launch a new container using all the exact same arguments as the
    # existing container (without having to pull in a python dependency)
    NEXT_CONTAINER_ID=$(
        $DOCKER_CMD run -d \
            --name "$CONTAINER_NAME" \
            --restart=always \
            --network "$NETWORK_MODE" \
            -v "device-certs:/etc/tedge/device-certs" \
            -v "mosquitto:/mosquitto/data" \
            -v /var/run/docker.sock:/var/run/docker.sock:rw \
            -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
            "$IMAGE"
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
    log "New image: $CONTAINER_IMAGE"

    return "$OK"
}

healthcheck() {
    log "Checking new container's health"
    sleep 2
    ATTEMPT=1
    TIMED_OUT=0
    while :; do
        if [ "$ATTEMPT" -gt 10 ]; then
            TIMED_OUT=1
            break
        fi
        if is_functional; then
            log "Container is working"
            break
        fi
        ATTEMPT=$((ATTEMPT+1))
        sleep 1
    done

    return "$TIMED_OUT"
}

rollback() {
    log "Rolling back"
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
        log "Warning: Failed to publish MQTT message" >&2
    fi
}

update_background() {
    log "Starting background container to perform the container update"

    PAYLOAD=$(
        printf '{"text":"%s","image":"%s","containerId":"%s"}' \
        "New thin-edge.io version detected. Starting background update from $TEDGE_VERSION" \
        "$CURRENT_CONTAINER_CONFIG_IMAGE" \
        "$CURRENT_CONTAINER_ID"
    )
    publish_message "e/tedge_self_update" "$PAYLOAD"

    OPTIONS=""
    if [ "$FORCE" = 1 ]; then
        OPTIONS="$OPTIONS --force"
    fi
    # shellcheck disable=SC2086
    set -- $OPTIONS
    # FIXME: Remove --rm option, and use a predictable name so that logs can be collected
    # to help debug a failed update
    UPDATER_CONTAINER_ID=$(
        $DOCKER_CMD run -d \
            --rm \
            -v /var/run/docker.sock:/var/run/docker.sock:rw \
            "$IMAGE" \
            "$0" update --image "$IMAGE" "$@"
    )
    log "Update container id: $UPDATER_CONTAINER_ID"

    # Set the container to restart (but only after the background service was launched successfully)
    log "Setting restart policy to no for existing container"
    $DOCKER_CMD container update "${CURRENT_CONTAINER_ID}" --restart no

    # wait for service to start and be stable
    sleep 5

    if ! is_container_running "$UPDATER_CONTAINER_ID"; then
        log "Container updater crashed. id=$UPDATER_CONTAINER_ID"
        exit "$FAILED"
    fi

    # Give some time for the message to be published
    sleep 5
}

#
# Argument parsing
#
ACTION=
UPDATE_LIST=

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit "$OK"
            ;;
        --image)
            IMAGE="$2"
            shift
            ;;
        --container-name)
            CONTAINER_NAME="$2"
            shift
            ;;
        --update-list)
            UPDATE_LIST="$2"
            shift
            ;;
        --force)
            FORCE=1
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
    is_update_requested)
        #
        # Determine if the software_update command includes a request
        # to update its own container.
        # Also parse the request and store the desired image
        #
        YES=0
        NO=1
        ERROR=2
        MODULE=$(echo "$UPDATE_LIST" | jq -r '.[] | select(.type == "self") | .modules | first | [.action, .name, .version] | @tsv' ||:)
        if [ -z "$MODULE" ]; then
            log "update list does not contain a self-update sm-plugin"
            exit "$NO"
        fi

        # name = Container name
        # version = Desired image (config) name. e.g. "latest" or "tedge-example" or "tedge-example:1.2.3"
        # Note, if 'latest' is used, then lookup the running container's currently configured image config name
        OP_ACTION=$(echo "$MODULE" | cut -f1)
        OP_NAME=$(echo "$MODULE" | cut -f2)
        OP_VERSION=$(echo "$MODULE" | cut -f3)

        log "Parsed module information. action=$OP_ACTION, name=$OP_NAME, version=$OP_VERSION"
        if [ "$OP_ACTION" != "install" ]; then
            log "Invalid action detected. Action must be set to 'install'. No other value is supported"
            exit "$ERROR"
        fi

        if [ -z "$OP_VERSION" ]; then
            log "module version is empty. The update request is too vague"
            exit "$NO"
        fi

        if [ "$OP_VERSION" = "latest" ]; then
            # Exclude the ":latest" suffix to allow using a local image. With ":latest", docker assumes it is a registry image
            # TODO: Check if this is intended behaviour
            OP_VERSION="$(echo "$CURRENT_CONTAINER_CONFIG_IMAGE" | cut -d: -f1)"
            log "Module image is set to 'latest' so assuming that the container config image should stay the same. new_image=$OP_VERSION"
        fi

        printf ':::begin-tedge:::\n'
        printf '{"containerName":"%s","image":"%s"}\n' "$OP_NAME" "$OP_VERSION"
        printf ':::end-tedge:::\n'
        exit "$YES"
        ;;
    version)
        prepare
        printf '%s\t%s:%s\n' "$CONTAINER_NAME" "$CURRENT_CONTAINER_CONFIG_IMAGE" "$TEDGE_VERSION"
        ;;
    operation_parameters)
        printf ':::begin-tedge:::\n'
        printf '{"image":"%s","containerName":"%s"}\n' "$IMAGE" "$CONTAINER_NAME"
        printf ':::end-tedge:::\n'
        exit "$OK"
        ;;
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
        PAYLOAD=$(
            printf '{"text":"%s","image":"%s","containerId":"%s"}' \
            "Successfully updated thin-edge.io to $TEDGE_VERSION" \
            "$CURRENT_CONTAINER_CONFIG_IMAGE" \
            "$CURRENT_CONTAINER_ID"
        )
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

