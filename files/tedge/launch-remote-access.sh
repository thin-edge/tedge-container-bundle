#!/bin/sh
set -e

DOCKER_CMD=docker
if ! docker ps >/dev/null 2>&1; then
    if command -V sudo >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi
fi

CONTAINER_NAME=${CONTAINER_NAME:-}
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME=$(hostname)
fi
CONTAINER_ID=$($DOCKER_CMD inspect "$CONTAINER_NAME" --format "{{.Id}}")

# use the same image as the current container
IMAGE=$($DOCKER_CMD inspect "$CONTAINER_ID" --format "{{.Config.Image}}")

# Inherit docker flags
# Note: The single quotes around 'EOT' prevents variable expansion
TEMPLATE=$(
    cat <<'EOT'
  {{- with .HostConfig}}
        {{- range $e := .ExtraHosts}}
  --add-host {{printf "%q" $e}} \
        {{- end}}
    {{- end}}
  {{- with .NetworkSettings -}}
        {{- range $n, $conf := .Networks}}
            {{- with $conf }}
  --network {{printf "%q" $n}} \
                {{- range $a := $conf.Aliases}} 
  --network-alias {{printf "%q" $a}} \
                {{- end}}
            {{- end}}
        {{- end}}
    {{- end}}
EOT
)
OPTIONS=$($DOCKER_CMD inspect "$CONTAINER_ID" --format "$TEMPLATE" | tr -d "\n\\\"")

TEDGE_C8Y_URL=$(tedge config get c8y.url)

# Launch an independent container to handle the remote access session
# so that it can do things like restarting this container
# shellcheck disable=SC2086
$DOCKER_CMD run --rm -d \
    $OPTIONS \
    -e TEDGE_MQTT_CLIENT_HOST="$CONTAINER_NAME" \
    -e TEDGE_C8Y_URL="$TEDGE_C8Y_URL" \
    "$IMAGE" \
    c8y-remote-access-plugin --child "$@"
