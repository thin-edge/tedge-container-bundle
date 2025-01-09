#!/bin/sh
set -e

set_state() {
    printf ":::begin-tedge:::\n%s\n:::end-tedge:::\n" "$1"
}

set_requires_restart() {
    STATE=$(printf '{"requiresRestart":true}\n')
    set_state "$STATE"
}

create_csr() {
    #
    # Create new CSR
    #
    device_id="$1"

    CSR_PATH=$(tedge config get device.csr_path)
    rm -f "$CSR_PATH"
    if [ -n "$device_id" ]; then
        tedge cert create-csr --device-id "$device_id"
    else
        tedge cert create-csr
    fi

    CSR_ENCODED=$(base64 -w 0 < "$CSR_PATH")

    STATE=$(printf '{"csr":"%s"}\n' "$CSR_ENCODED")
    set_state "$STATE"
}

update_certificate() {
    #
    # Set the device certificate
    #
    encoded_cert="$1"
    CERT_PATH=$(tedge config get device.cert_path)
    echo "$encoded_cert" | base64 -d > "${CERT_PATH}.tmp"

    # Check if certificate has changed
    CURRENT_CHECKSUM=$(sha256sum "$CERT_PATH" ||:)
    TARGET_CHECKSUM=$(sha256sum "${CERT_PATH}.tmp" ||:)

    if [ "$CURRENT_CHECKSUM" = "$TARGET_CHECKSUM" ]; then
        echo "No change in certificate is detected. path=${CERT_PATH}"
        return 0
    fi

    # use mv as it is atomic
    echo "Updating device public certificate: ${CERT_PATH}" >&2
    mv "${CERT_PATH}.tmp" "${CERT_PATH}"
    set_requires_restart
}

set_c8y_url() {
    #
    # Set the thin-edge.io c8y.url config
    #
    target="$1"
    current=$(tedge config get c8y.url)

    if [ "$target" != "$current" ]; then
        tedge config set c8y.url "$target"

        set_requires_restart
    else
        echo "c8y.url is already set to '$target'. Nothing to do" >&2
        # nothing to do
        exit 100
    fi
}

ACTION="$1"
shift
case "$ACTION" in
    restart_required)
        if [ "$1" = "true" ]; then
            echo "Restart is required" >&2
            exit 0
        fi
        exit 1
        ;;

    set_c8y_url)
        if [ -n "$1" ]; then
            set_c8y_url "$1"
        else
            echo "Operation does not container a c8y.url, so skipping this step" >&2
        fi
        ;;

    create_csr)
        DEVICE_ID="$1"
        create_csr "$DEVICE_ID"
        ;;
    
    update_certificate)
        if [ -n "$1" ]; then
            update_certificate "$1"
        else
            echo "No new certificate was provided, so skipping step" >&2
        fi
        ;;
    *)
        echo "Unknown action in $0" >&2
        exit 1
        ;;
esac

exit 0
