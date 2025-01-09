#!/bin/sh
set -e

set_state() {
    printf ":::begin-tedge:::\n%s\n:::end-tedge:::\n" "$1"
}

create_csr() {
    #
    # Create new CSR
    #
    device_id=

    if [ $# -gt 0 ]; then
        device_id="$1"
    fi

    CSR_PATH=$(tedge config get device.csr_path)
    rm -f "$CSR_PATH"
    if [ -n "$device_id" ]; then
        tedge cert create-csr --device-id "$device_id"
    else
        tedge cert create-csr
    fi

    CSR_ENCODED=$(base64 -w 0 < "$CSR_PATH")

    STATE=$(printf '{"csr":"%s","requiresRestart":true}\n' "$CSR_ENCODED")
    set_state "$STATE"
}

update_certificate() {
    #
    # Set the device certificate
    #
    encoded_cert="$1"
    CERT_PATH=$(tedge config get device.cert_path)
    # use mv as it is atomic
    echo "$encoded_cert" | base64 -d > "${CERT_PATH}.tmp"
    mv "${CERT_PATH}.tmp" "${CERT_PATH}"
}

set_c8y_url() {
    #
    # Set the thin-edge.io c8y.url config
    #
    target="$1"
    current=$(tedge config get c8y.url)

    if [ "$target" != "$current" ]; then
        tedge config set c8y.url

        STATE=$(printf '{"requiresRestart":true}\n')
        set_state "$STATE"
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
        if [ $# -gt 0 ]; then
            create_csr "$DEVICE_ID"
            DEVICE_ID="$1"
        fi
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
