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

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

IMAGE="${IMAGE:-}"

CONTAINER_NAME="${CONTAINER_NAME:-tedge}"
CURRENT_IMAGE_ID=
TARGET_IMAGE_ID=
FORCE=0

# golang template to set container run options (from an existing container)
RUN_TEMPLATE_FILE=${RUN_TEMPLATE_FILE:-/usr/share/tedge/container_run.tpl}

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
    # Use container id to prevent any unexpected changes
    if [ -z "$CURRENT_CONTAINER_ID" ]; then
        log "Reading container configuration by name. name=$CONTAINER_NAME"
        CURRENT_CONTAINER_ID=$($DOCKER_CMD inspect "$CONTAINER_NAME" --format "{{.Id}}" ||:)
    else
        log "Reading container configuration by id. id=$CURRENT_CONTAINER_ID"
    fi
    CURRENT_CONTAINER_CONFIG_IMAGE=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Config.Image}}" ||:)

    if [ -z "$IMAGE" ]; then
        value=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Config.Image}}" ||:)
        if [ -n "$value" ]; then
            IMAGE="$value"
            log "Detected container image from container. id=$CURRENT_CONTAINER_ID, image=$value"
        fi
    fi
}

needs_update() {
    CURRENT_IMAGE_ID=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Image}}" ||:)
    CURRENT_IMAGE_NAME=$($DOCKER_CMD inspect "$CURRENT_CONTAINER_ID" --format "{{.Config.Image}}" ||:)
    log "Current container. imageId=$CURRENT_IMAGE_ID, imageName=$CURRENT_IMAGE_NAME"

    case "${1:-}" in
        pull)
            log "Trying to pull new image: ${IMAGE}"
            if $DOCKER_CMD pull "$IMAGE"; then
                log "Successfully pulled new image"
            else
                log "Failed to pull image. Trying to continue"
            fi
            ;;
    esac

    TARGET_IMAGE_ID=$($DOCKER_CMD image inspect "$IMAGE" --format "{{.Id}}")

    if [ "$FORCE" = 1 ]; then
        log "Forcing a container update"
        return "$OK"
    fi

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
    container_id="$1"
    attempt=1
    while [ "$attempt" -le 90 ]; do
        if ! is_container_running "$container_id"; then
            return "$OK"
        fi
        attempt=$((attempt+1))
        sleep 1
    done
    return "$FAILED"
}

read_container_run_template() {
    #
    # Read the contents of the first docker run template file found
    # Return an error if no file is found
    #
    for template_file in "$@"; do
        if [ -f "$template_file" ]; then
            cat "$template_file"
            return
        fi
    done

    log "Could not find a container run template"
    return 1
}

generate_run_command_from_container() {
    #
    # Generate a docker run script based on an existing container
    # so a new container with a new image can be launched in a similar way
    #
    container_spec="$1"
    image="$2"

    # Use first existing tmeplate
    # Include looking for template locally to make it easier to run locally during development
    RUN_TEMPLATE=$(
        read_container_run_template \
            "$RUN_TEMPLATE_FILE" \
            "$SCRIPT_DIR/container_run.tpl"
    )

    RUN_OPTIONS=$($DOCKER_CMD inspect "$container_spec" --format "$RUN_TEMPLATE")
    RUN_SCRIPT_CONTENTS=$(
        cat <<EOT
#!/bin/sh
set -e
$DOCKER_CMD run -d \\$RUN_OPTIONS
  $image
EOT
    )
    
    # Note: Remove some options as these should be controlled by the container image itself,
    # and not be copied when spawning a new container (as they come from the container itself)
    # It is difficult to check which options are coming from defaults in the container
    # and what came from the user as docker does not differentiate between the two after the container is created
    TMP_RUN_SCRIPT="$(mktemp)"
    echo "$RUN_SCRIPT_CONTENTS" \
    | sed '/--label "org.opencontainers.image/d' \
    | sed '/--env "S6_/d' \
    | sed '/--env "PATH=/d' \
    > "$TMP_RUN_SCRIPT"
    chmod +x "$TMP_RUN_SCRIPT"
    echo "$TMP_RUN_SCRIPT"
}

update() {
    log "Waiting for existing container to shutdown. name=$CONTAINER_NAME, id=$CURRENT_CONTAINER_ID"

    # Wait for the container to stop (this is the hand-off)
    if ! wait_for_stop "$CURRENT_CONTAINER_ID"; then
        log "Container was not shutdown. Aborting update"
        exit "$FAILED"
    fi

    # Make sure the container is stopped and not in the process of restarting
    $DOCKER_CMD stop --time 90 "$CURRENT_CONTAINER_ID" ||:

    # Generate run container before the container is renamed so the name is preserved
    RUN_SCRIPT=$(generate_run_command_from_container "$CURRENT_CONTAINER_ID" "$IMAGE")

    # remove any existing backup-name
    if $DOCKER_CMD inspect "$BACKUP_CONTAINER_NAME" >/dev/null 2>&1; then
        $DOCKER_CMD stop "$BACKUP_CONTAINER_NAME" >/dev/null ||:
        $DOCKER_CMD rm "$BACKUP_CONTAINER_NAME" >/dev/null ||:
    fi
    log "Renaming existing container. old=${CONTAINER_NAME}, new=$BACKUP_CONTAINER_NAME"
    $DOCKER_CMD container rename "$CURRENT_CONTAINER_ID" "$BACKUP_CONTAINER_NAME"

    log "Starting the tedge container. name=$CONTAINER_NAME, run_script=$RUN_SCRIPT"
    log "Run script: $(cat "$RUN_SCRIPT")"
    NEXT_CONTAINER_ID=$(
        "$RUN_SCRIPT"
    )

    log "Removing temporary container run script: $RUN_SCRIPT"
    rm -f "$RUN_SCRIPT"
}

is_functional() {
    container_id="$1"
    # Check container state
    IS_RUNNING=$($DOCKER_CMD inspect "$container_id" --format "{{.State.Running}}" 2>/dev/null ||:)
    if [ "$IS_RUNNING" != true ]; then
        return "$FAILED"
    fi

    # Check cloud connectivity
    if $DOCKER_CMD exec -t "$container_id" tedge config get c8y.url; then
        if ! $DOCKER_CMD exec -t "$container_id" tedge connect c8y --test; then
            return "$FAILED"
        fi
    fi

    if $DOCKER_CMD exec -t "$container_id" tedge config get aws.url; then
        if ! $DOCKER_CMD exec -t "$container_id" tedge connect aws --test; then
            return "$FAILED"
        fi
    fi

    if $DOCKER_CMD exec -t "$container_id" tedge config get az.url; then
        if ! $DOCKER_CMD exec -t "$container_id" tedge connect az --test; then
            return "$FAILED"
        fi
    fi

    CONTAINER_IMAGE=$($DOCKER_CMD inspect "$container_id" --format "{{.Image}}")
    log "New image: $CONTAINER_IMAGE"

    return "$OK"
}

healthcheck() {
    container_id="$1"
    log "Checking new container's health. id=$container_id"
    sleep 2
    ATTEMPT=1
    TIMED_OUT=0
    while :; do
        if [ "$ATTEMPT" -gt 10 ]; then
            TIMED_OUT=1
            break
        fi
        if is_functional "$container_id"; then
            log "Container is working"
            break
        fi
        ATTEMPT=$((ATTEMPT+1))
        sleep 10
    done

    return "$TIMED_OUT"
}

rollback() {
    log "Rolling back container. name=$CONTAINER_NAME (unhealthy)"

    if ! $DOCKER_CMD inspect "$BACKUP_CONTAINER_NAME" >/dev/null 2>&1; then
        # Don't do anything if the backup does not exist, as a broken container is better then no container!
        log "ERROR: Could not rollback container as the backup no longer exists! This is unexpected. name=$BACKUP_CONTAINER_NAME"
        exit 1
    fi

    log "Stopping unhealthy container. name=$CONTAINER_NAME"
    $DOCKER_CMD stop "$CONTAINER_NAME" ||:
    $DOCKER_CMD rm "$CONTAINER_NAME" ||:

    log "Restoring container from backup. name=$BACKUP_CONTAINER_NAME (new name will be $CONTAINER_NAME)"
    $DOCKER_CMD container rename "$BACKUP_CONTAINER_NAME" "$CONTAINER_NAME"
    $DOCKER_CMD container update "$CONTAINER_NAME" --restart always
    $DOCKER_CMD start "$CONTAINER_NAME" ||:

    log "Performing a healthcheck on the restored container (for information purposes only)"
    if healthcheck "$CONTAINER_NAME"; then
        log "Rollback was successful and the container is functioning"
    else
        log "Rollback was successful but container healthcheck failed, though this could fail if the cloud connectivity is down"
    fi
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

    if $DOCKER_CMD inspect "$UPDATER_CONTAINER_NAME" >/dev/null 2>&1; then
        log "Removing old updater container. name=$UPDATER_CONTAINER_NAME"
        $DOCKER_CMD stop "$UPDATER_CONTAINER_NAME" 2>/dev/null ||:
        $DOCKER_CMD rm "$UPDATER_CONTAINER_NAME" 2>/dev/null ||:
    fi
    UPDATER_CONTAINER_ID=$(
        $DOCKER_CMD run -d \
            --name "$UPDATER_CONTAINER_NAME" \
            -v /var/run/docker.sock:/var/run/docker.sock:rw \
            "$IMAGE" \
            "$0" update --image "$IMAGE" --container-name "$CONTAINER_NAME" --container-id "$CURRENT_CONTAINER_ID" "$@"
    )
    log "Updater container. id=$UPDATER_CONTAINER_ID, name=$UPDATER_CONTAINER_NAME"

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

collect_update_logs() {
    # Collect updater container logs
    if $DOCKER_CMD inspect "$UPDATER_CONTAINER_NAME" >/dev/null 2>&1; then

        log "Waiting for updater container to stop (if it is running). name=$UPDATER_CONTAINER_NAME"
        if ! wait_for_stop "$UPDATER_CONTAINER_NAME"; then
            log "Updater container is still running. Collecting logs anyway"
        fi

        log "Collecting updater container logs. name=$UPDATER_CONTAINER_NAME"
        log "----- Start of updater logs -----"
        $DOCKER_CMD logs "$UPDATER_CONTAINER_NAME" -n 500 >&2 ||:
        log "----- End of updater logs -----"
    else
        log "Updater container does not exist so no logs to collect. name=$UPDATER_CONTAINER_NAME"
    fi
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
        --container-id)
            CURRENT_CONTAINER_ID="$2"
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

# Set container names which are derived from the container name
BACKUP_CONTAINER_NAME="${CONTAINER_NAME}-bak"
UPDATER_CONTAINER_NAME="${CONTAINER_NAME}-updater"

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
        prepare
        collect_update_logs
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
    print_run_command)
        # Help debug the docker run arguments (inferred from an already spawned container)
        echo "" >&2
        echo "The following command is used to spawn a new container (copying from an already running container)" >&2
        echo "" >&2
        RUN_SCRIPT=$(generate_run_command_from_container "$CONTAINER_NAME" "${IMAGE:-tedge}")
        cat "$RUN_SCRIPT"
        rm -f "$RUN_SCRIPT"
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

        if ! healthcheck "$CONTAINER_NAME"; then
            rollback
        fi
        ;;
    *)
        echo "Unknown command. $ACTION" >&2
        usage
        exit "$FAILED"
        ;;
esac

