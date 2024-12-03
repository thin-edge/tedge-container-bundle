#!/bin/sh
set -e

REMOTE_ACCESS_DISABLE_CONTAINER_SPAWN="${REMOTE_ACCESS_DISABLE_CONTAINER_SPAWN:-0}"

SUDO=
if command -V sudo >/dev/null 2>&1; then
    SUDO="sudo -E"
fi

has_container_api_access() {
    $SUDO tedge-container self list >/dev/null 2>&1
}

if [ "$REMOTE_ACCESS_DISABLE_CONTAINER_SPAWN" = 1 ] || ! has_container_api_access; then
    echo "Launching session as a child process"
    c8y-remote-access-plugin "$@"
    exit 0
fi

echo "Launching session in an independent container"
$SUDO tedge-container tools run-in-context --name-prefix remoteaccess-connect --rm -- c8y-remote-access-plugin --child "$@"
exit 0
