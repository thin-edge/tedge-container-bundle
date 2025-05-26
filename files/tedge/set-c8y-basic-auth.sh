#!/bin/sh
set -e
if [ $# -lt 2 ]; then
    echo "ERROR: Expected 2 arguments." >&2
    echo "USAGE: $0 <C8Y_DEVICE_USER> <C8Y_DEVICE_PASSWORD>" >&2
    exit 1
fi
CREDENTIALS_PATH=$(tedge config get c8y.credentials_path)
printf '[c8y]\nusername = "%s"\npassword = "%s"\n' "$1" "$2" > "$CREDENTIALS_PATH"
chmod 600 "$CREDENTIALS_PATH"
