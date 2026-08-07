#!/bin/sh
set -e

export RENEW_WITH_CA="${RENEW_WITH_CA:-c8y}"
export CERT_RENEW_PUBLISH_EVENTS="${CERT_RENEW_PUBLISH_EVENTS:-1}"
MAPPERS=

if [ "$SERVICE_TEDGE_MAPPER_C8Y" = 1 ]; then
    MAPPERS="c8y"
fi

if [ -z "$MAPPERS" ]; then
    echo "No mappers specified, so nothing to renew" >&2
    exit 0
fi

try_publish_event() {
    TYPE="$1"
    MESSAGE="$2"
    if [ "$CERT_RENEW_PUBLISH_EVENTS" = 1 ]; then
        timeout 10 tedge mqtt pub "te/device/main///e/$TYPE" "{\"text\":\"$MESSAGE\"}" ||:
    fi
}

renew_cert() {
    NAME="$1"
    if tedge cert needs-renewal "$NAME"; then
        if tedge cert renew "$NAME" --ca "${RENEW_WITH_CA}"; then
            if ! tedge reconnect "$NAME"; then
                try_publish_event "certificate_renewal_failed" "Failed to reconnect after renewing certificate for $NAME mapper"
                return 1
            fi
            rm -f "$(tedge config get "$NAME".device.cert_path).new"
            try_publish_event "certificate_renewal" "Successfully renewed certificate for $NAME mapper"
            return 0
        else
            try_publish_event "certificate_renewal_failed" "Failed to renew certificate for $NAME mapper"
        fi
    else
        echo "Certificate does not need renewing. mapper=$NAME" >&2
    fi
}

uses_cumulocity_ca() {
    NAME="$1"
    tedge cert show "$NAME" | grep "^Issuer:" | grep -q "CN=t[0-9]*"
}

for MAPPER in $MAPPERS; do
    if uses_cumulocity_ca "$MAPPER" >/dev/null 2>&1; then
        renew_cert "$MAPPER" ||:
    fi
done
