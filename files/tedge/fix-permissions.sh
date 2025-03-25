#!/bin/sh
set -e
# Enforce permissions in cases where the base image has changed the UID and GID across container updates
if [ "$(id -u)" != 0 ]; then
    echo "Skipping fixing of ownership as the script was not called as root. script=$0" >&2
    exit 0
fi

echo "Changing ownership of thin-edge.io folders" >&2
[ -d "$DATA_DIR" ] && chown -R tedge:tedge "$DATA_DIR"
[ -d /etc/tedge ] && chown -R tedge:tedge /etc/tedge
[ -d /var/tedge ] && chown -R tedge:tedge /var/tedge
