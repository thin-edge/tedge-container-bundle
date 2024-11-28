#!/bin/sh
# Compatibility script for updating of images from older versions <= 20241126.1855
#

#
# Argument parsing
#
ACTION="$1"
shift

IMAGE=
CURRENT_CONTAINER_ID=

DOCKER_CMD=docker
if ! docker ps >/dev/null 2>&1; then
    if command -V sudo >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --image)
            IMAGE="$2"
            shift
            ;;
        --container-name)
            # not used
            shift
            ;;
        --container-id)
            CURRENT_CONTAINER_ID="$2"
            shift
            ;;
    esac
    shift
done

case "$ACTION" in
    update)
        # In previous images, only docker was supported
        echo "Calling legacy update script (upgrading from an image <= 20241126.1855)"
        $DOCKER_CMD run -t --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            "$IMAGE" sudo tedge-container tools container-clone --container "$CURRENT_CONTAINER_ID" --image "$IMAGE"
        ;;
esac
