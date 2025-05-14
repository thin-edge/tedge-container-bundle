#!/command/with-contenv sh
# shellcheck shell=sh
set -e
echo "Current User: $(whoami)"

# Cumulocity certificate-authority feature
CA=${CA:-self-signed}
SHOW_REGISTRATION_BANNER=${SHOW_REGISTRATION_BANNER:-0}

# DEVICE_ID is only used for the initial device enrollment
# afterwards the device.id is taken from the device's certificate
DEVICE_ID=${DEVICE_ID:-}
DEVICE_ONE_TIME_PASSWORD=${DEVICE_ONE_TIME_PASSWORD:-}

# Use default value based on the hostname
if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID="tedge_$(hostname || host)"
fi

MAX_CONNECT_ATTEMPTS=${MAX_CONNECT_ATTEMPTS:-5}
MAX_RANDOM_WAIT=${MAX_RANDOM_WAIT:-15}

DATA_DIR=${DATA_DIR:-/data/tedge}
# Use PERSIST_TEDGE_TOML=1 to enable creating a symlink for the /etc/tedge/tedge.toml
# to /data/tedge/tedge.toml, to allow persisting tedge.toml info across upgrades
PERSIST_TEDGE_TOML=${PERSIST_TEDGE_TOML:-1}

#
# device certificate loaders
#
load_from_env() {
    #
    # Load certificate (base64 encoded) from env variables
    # Note: Use if one of CERTPRIVATE or CERTPUBLIC is provided, as
    # the private key is optional when using the pkcs11 (cryptoki) interface
    #
    if [ -z "${CERTPRIVATE:-}" ] && [ -z "${CERTPUBLIC:-}" ]; then
        return 1
    fi
    echo "Loading device certificate from environment variables" >&2

    if [ -n "${CERTPRIVATE:-}" ]; then
        echo "Writing thin-edge.io private key from env 'CERTPRIVATE' (decoding from base64) to file" >&2
        CERT_FILE_KEY="$(tedge config get device.key_path)"
        printf '%s' "$CERTPRIVATE" | tr -d '"' | base64 -d > "$CERT_FILE_KEY"
        chmod 600 "$CERT_FILE_KEY"
    fi

    if [ -n "${CERTPUBLIC:-}" ]; then
        echo "Writing thin-edge.io private key from env 'CERTPUBLIC' (decoding from base64) to file" >&2
        CERT_FILE_PUB="$(tedge config get device.cert_path)"
        printf '%s' "$CERTPUBLIC" | tr -d '"' | base64 -d > "$CERT_FILE_PUB"
        chmod 644 "$CERT_FILE_PUB"
    fi
}

load_from_secrets() {
    #
    # Load certificates from docker secrets, see https://docs.docker.com/reference/cli/docker/secret/create/
    # Note: Due to permissions problems, copy the secrets from the /run read-only path to /etc/tedge/device-certs/
    #
    if [ ! -f /run/secrets/certificate_private_key ] || [ ! -f /run/secrets/certificate_public_key ]; then
        return 1
    fi

    echo "Loading device certificate from docker secrets" >&2

    CERT_FILE_KEY="$(tedge config get device.key_path)"
    cat /run/secrets/certificate_private_key > "$CERT_FILE_KEY"
    chmod 600 "$CERT_FILE_KEY"

    CERT_FILE_PUB="$(tedge config get device.cert_path)"
    cat /run/secrets/certificate_public_key > "$CERT_FILE_PUB"
    chmod 644 "$CERT_FILE_PUB"
}

load_from_file() {
    CERT_FILE_KEY="$(tedge config get device.key_path)"
    CERT_FILE_PUB="$(tedge config get device.cert_path)"

    if [ ! -f "$CERT_FILE_KEY" ] || [ ! -f "$CERT_FILE_PUB" ]; then
        return 1
    fi

    # Don't actually do anything, but confirm the presence of device certificates
    echo "Loading device certificates from file (no-op)"
}

create_tedge_config_symlink() {
    # Store the tedge.toml under the data dir, and
    # use a symlink from /etc/tedge/tedge.toml to point to the data dir.
    # This enables users to retain customized tedge.toml files across container
    # updates
    DATA_DIR_TEDGE_TOML="$DATA_DIR/tedge.toml"
    ETC_TEDGE_TOML="/etc/tedge/tedge.toml"

    if [ ! -d "$DATA_DIR" ]; then
        echo "Warning: Data dir does not exist, so skipping creation of symlink under $DATA_DIR" >&2
        return 0
    fi

    if [ -L "$ETC_TEDGE_TOML" ]; then
        echo "tedge.toml symlink already exists. path=$ETC_TEDGE_TOML" >&2
        return 0
    fi

    # move any existing tedge.toml to data dir (if it does not already exist)
    if [ ! -f "$DATA_DIR_TEDGE_TOML" ]; then
        if [ -f "$ETC_TEDGE_TOML" ]; then
            echo "Moving existing tedge.toml file from $ETC_TEDGE_TOML to $DATA_DIR_TEDGE_TOML" >&2
            cp "$ETC_TEDGE_TOML" "$DATA_DIR_TEDGE_TOML"
            rm -f "$ETC_TEDGE_TOML"
        else
            echo "Creating empty file"
            touch "$DATA_DIR_TEDGE_TOML"
        fi
    fi

    echo "Creating symlink from $DATA_DIR_TEDGE_TOML to /etc/tedge/tedge.toml" >&2
    ln -sf "$DATA_DIR_TEDGE_TOML" "$ETC_TEDGE_TOML" || echo "Warning: Failed to create tedge.toml symlink" >&2
    echo "Successfully created tedge.toml symlink" >&2
}

############
# Main
############
# fix permissions in case if the tedge user has had its uid/gid changed across a container update
if command -V sudo >/dev/null 2>&1; then
    export DATA_DIR
    sudo -E DATA_DIR="$DATA_DIR" /usr/bin/fix-permissions.sh
fi

if [ "$PERSIST_TEDGE_TOML" = 1 ]; then
    create_tedge_config_symlink
fi

# Create the agent state folder
AGENT_STATE=$(tedge config get agent.state.path)
mkdir -p "$AGENT_STATE"

#
# Try loading the device certificates from several locations, taking the first successful function
# Don't fail as users are allowed to start up a container without a device certificate (e.g. when only running the tedge-agent)
#
load_from_env || load_from_secrets || load_from_file ||:


# Support variable set by go-c8y-cli
if [ -n "$C8Y_DOMAIN" ] && [ -z "${TEDGE_C8Y_URL:-}" ]; then
    echo "Setting c8y.url from C8Y_DOMAIN env variable. $C8Y_DOMAIN" >&2
    tedge config set c8y.url "$C8Y_DOMAIN"
fi

random_sleep() {
    VALUE=$(awk "BEGIN { srand(); print int(rand()*32768 % $MAX_RANDOM_WAIT) }")
    echo "Sleeping ${VALUE}s" >&2
    sleep "$VALUE" 
}

get_random_code() {
    awk '
function rand_string(n,         s,i) {
    for ( i=1; i<=n; i++ ) {
        s = s chars[int(1+rand()*numChars)]
    }
    return s
}
BEGIN{
    srand()
    for (i=48; i<=122; i++) {
        char = sprintf("%c", i)
        if ( char ~ /[[:alnum:]]/ ) {
            chars[++numChars] = char
        }
    }

    for (i=1; i<=1; i++) {print rand_string(30)}
}'
}

show_registration_banner() {
    TARGET_URL=$(tedge config get c8y.http 2>/dev/null ||:)
    cat <<EOT
------------------------------------------------------
Cumulocity Registration URL
------------------------------------------------------

https://${TARGET_URL}/apps/devicemanagement/index.html#/deviceregistration?externalId=${DEVICE_ID}&one-time-password=${DEVICE_ONE_TIME_PASSWORD}

EOT
}

#
# Connect the mappers (if they are configured and not already connected)
#
MAPPERS="c8y az aws"
for MAPPER in $MAPPERS; do
    if tedge config get "${MAPPER}.url" 2>/dev/null; then

        case "$MAPPER" in
            c8y)
                if [ "$CA" = "c8y" ]; then
                    # Register device using the Cumulocity certificate-authority feature
                    PUBLIC_CERT=$(tedge config get device.cert_path 2>/dev/null ||:)
                    if [ ! -f "$PUBLIC_CERT" ]; then
                        if [ -z "$DEVICE_ONE_TIME_PASSWORD" ]; then
                            DEVICE_ONE_TIME_PASSWORD=$(get_random_code)
                            SHOW_REGISTRATION_BANNER=1
                        fi

                        if [ "$SHOW_REGISTRATION_BANNER" = 1 ]; then
                            show_registration_banner
                        fi

                        # Download certificate
                        echo "Downloading certificate. device-id=$DEVICE_ID" >&2
                        if ! tedge cert download c8y --device-id "$DEVICE_ID" --one-time-password "$DEVICE_ONE_TIME_PASSWORD" --retry-every 5s --max-timeout 300s; then
                            echo "WARNING: Failed to download certificate" >&2
                        fi
                    fi
                fi
                ;;
        esac

        # Connect (with retries)
        attempt=1
        while :; do
            if tedge reconnect "$MAPPER"; then
                echo "Successfully connected to $MAPPER" >&2
                break
            fi
            if [ "$attempt" -ge "$MAX_CONNECT_ATTEMPTS" ]; then
                echo "Couldn't connect to $MAPPER but continuing anyway" >&2
                break
            fi
            attempt=$((attempt + 1))
            random_sleep
        done
    fi
done

# Check which bridges are present
echo "--- mosquitto-conf directory ---" >&2
ls -l /etc/tedge/mosquitto-conf/
