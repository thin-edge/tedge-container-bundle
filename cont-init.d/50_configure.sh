#!/command/with-contenv sh
# shellcheck shell=sh
set -e
echo "Current User: $(whoami)"

#
# Note: Due to permissions problems, copy the secrets from the /run read-only path to /etc/tedge/device-certs/
#
CERT_FILE_KEY="$(tedge config get device.key_path)"
if [ -f /run/secrets/certificate_private_key ]; then
    cat /run/secrets/certificate_private_key > "$CERT_FILE_KEY"
    chmod 600 "$CERT_FILE_KEY"
fi

CERT_FILE_PUB="$(tedge config get device.cert_path)"
if [ -f /run/secrets/certificate_public_key ]; then
    cat /run/secrets/certificate_public_key > "$CERT_FILE_PUB"
    chmod 644 "$CERT_FILE_PUB"
fi

# Support variable set by go-c8y-cli
if [ -n "$C8Y_DOMAIN" ] && [ -z "${TEDGE_C8Y_URL:-}" ]; then
    echo "Setting c8y.url from C8Y_DOMAIN env variable. $C8Y_DOMAIN" >&2
    tedge config set c8y.url "$C8Y_DOMAIN"
fi

#
# Connect the mappers (if they are configured and not already connected)
#
MAPPERS="c8y az aws"
for MAPPER in $MAPPERS; do
    if tedge config get "${MAPPER}.url" 2>/dev/null; then
        tedge connect "$MAPPER" ||:
    fi
done
