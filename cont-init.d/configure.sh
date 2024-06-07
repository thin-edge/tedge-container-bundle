#!/command/with-contenv sh
set -e
#
# Convert environment variables config to files
#
echo "Current User: $(whoami)"

if [ -n "$CERTPRIVATE" ]; then
    echo "Writing thin-edge.io private key from env 'CERTPRIVATE' (decoding from base64) to file" >&2
    CERT_FILE_KEY="$(tedge config get device.key_path)"
    printf '%s' "$CERTPRIVATE" | tr -d '"' | base64 -d > "$CERT_FILE_KEY"
    chmod 600 "$CERT_FILE_KEY"
fi


if [ -n "$CERTPUBLIC" ]; then
    echo "Writing thin-edge.io private key from env 'CERTPUBLIC' (decoding from base64) to file" >&2
    CERT_FILE_PUB="$(tedge config get device.cert_path)"
    printf '%s' "$CERTPUBLIC" | tr -d '"' | base64 -d > "$CERT_FILE_PUB"
    chmod 644 "$CERT_FILE_PUB"
fi

#
# Connect the mappers (if they are configured and not already connected)
#
MAPPERS="c8y az aws"
for MAPPER in $MAPPERS; do
    URL=$(tedge config get "${MAPPER}.url" 2>/dev/null)
    if [ -n "$URL" ]; then
        if ! tedge connect "$MAPPER" --test 2>/dev/null; then
            echo "Connecting $MAPPER" >&2
            tedge reconnect "$MAPPER" ||:
        fi
    fi
done
