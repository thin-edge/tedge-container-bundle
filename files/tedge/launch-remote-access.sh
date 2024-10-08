#!/bin/sh
set -e

# Disable spawning from a container
REMOTE_ACCESS_DISABLE_CONTAINER_SPAWN=${REMOTE_ACCESS_DISABLE_CONTAINER_SPAWN:-0}

if ! command -V docker >/dev/null 2>&1 || [ ! -e /var/run/docker.sock ] || [ "$REMOTE_ACCESS_DISABLE_CONTAINER_SPAWN" = 1 ]; then
    echo "Launching session as a child process"
    c8y-remote-access-plugin "$@"
    exit 0
fi

echo "Launching session in an independent container"
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
            {{- end}}
        {{- end}}
    {{- end}}
EOT
)
OPTIONS=$($DOCKER_CMD inspect "$CONTAINER_ID" --format "$TEMPLATE" | tr -d "\n\\\"")

TEDGE_C8Y_URL=$(tedge config get c8y.url)

# Add a host alias so the spawned container can reference the MQTT broker in the current container
MQTT_CLIENT_HOST=$($DOCKER_CMD inspect "$CONTAINER_ID" --format "{{.NetworkSettings.IPAddress}}" ||:)
if [ -z "$MQTT_CLIENT_HOST" ]; then
    echo "Getting container ip address from hostname"
    MQTT_CLIENT_HOST=$(getent hosts "$CONTAINER_NAME" | cut -d' ' -f1)
fi

echo "Running command"
set -x
# Launch an independent container to handle the remote access session
# so that it can do things like restarting this container
# shellcheck disable=SC2086
$DOCKER_CMD run --rm -d \
    $OPTIONS \
    --add-host tedge:"$MQTT_CLIENT_HOST" \
    -e TEDGE_MQTT_CLIENT_HOST=tedge \
    -e TEDGE_C8Y_URL="$TEDGE_C8Y_URL" \
    "$IMAGE" \
    c8y-remote-access-plugin --child "$@"
