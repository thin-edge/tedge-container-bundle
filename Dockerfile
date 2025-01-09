ARG TEDGE_TAG=1.4.1
# thin-edge.io base image name: tedge, tedge-main
ARG TEDGE_IMAGE=tedge
FROM ghcr.io/thin-edge/${TEDGE_IMAGE}:${TEDGE_TAG}
ARG TARGETPLATFORM
ARG S6_OVERLAY_VERSION=3.2.0.0
ARG DATA_DIR=/data/tedge

USER root

# Notes: ca-certificates is required for the initial connection with c8y, otherwise the c8y cert is not trusted
# to test out the connection. But this is only needed for the initial connection, so it seems unnecessary
RUN apk add --no-cache \
        mosquitto \
        jq \
        bash \
        curl \
        sudo

# Install s6-overlay
# Based on https://github.com/just-containers/s6-overlay#which-architecture-to-use-depending-on-your-targetarch
RUN case ${TARGETPLATFORM} in \
        "linux/amd64")  S6_ARCH=x86_64  ;; \
        "linux/arm64")  S6_ARCH=aarch64  ;; \
        "linux/arm/v6")  S6_ARCH=armhf  ;; \
        "linux/arm/v7")  S6_ARCH=arm  ;; \
        *) echo "Unsupported target platform: TARGETPLATFORM=$TARGETPLATFORM"; exit 1 ;; \
    esac \
    && curl https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz -L -s --output /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && curl https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz -L -s --output /tmp/s6-overlay-${S6_ARCH}.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz \
    && rm -f /tmp/s6-overlay-noarch.tar.xz \
    && rm -f /tmp/s6-overlay-${S6_ARCH}.tar.xz

# Add custom service definitions (e.g. s6-overlay) and community plugins
RUN rm -f /etc/tedge/system.toml
RUN wget -O - https://thin-edge.io/install-services.sh | sh -s -- s6_overlay \
    && apk add --no-cache \
        tedge-command-plugin \
        tedge-apk-plugin \
        # Enable easier management of containers using docker compose
        # without requiring the cli to be installed on the host (as read-only filesystems)
        # might not have access to it
        # Note: Volumes should be configured to persist the docker compose files
        docker-cli-compose \
        tedge-container-plugin-ng \
    # Support updating from older images which still use the deprecated self type
    && ln -s /usr/bin/tedge-container /etc/tedge/sm-plugins/self

# Set permissions of all files under /etc/tedge
# TODO: Can thin-edge.io set permissions during installation?
RUN chown -R tedge:tedge /etc/tedge \
    && echo "tedge  ALL = (ALL) NOPASSWD:SETENV: /usr/bin/tedge, /etc/tedge/sm-plugins/[a-zA-Z0-9]*, /bin/sync, /sbin/init, /usr/bin/tedgectl, /bin/kill, /usr/bin/tedge-container, /usr/bin/docker, /usr/bin/podman, /usr/bin/podman-remote, /usr/bin/podman-compose" >/etc/sudoers.d/tedge
# Custom init. scripts - e.g. write env variables data to files
COPY cont-init.d/*  /etc/cont-init.d/

# mosquitto configuration
COPY files/mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf
RUN mkdir -p "$DATA_DIR" \
    && chown -R tedge:tedge "$DATA_DIR" \
    && sed -i "s|persistence_location .*|persistence_location $DATA_DIR/|g" /etc/mosquitto/mosquitto.conf

# Add custom thin-edge.io configuration (e.g. plugin config)
COPY files/tedge/tedge.toml /etc/tedge/
COPY files/tedge/plugins/*.toml /etc/tedge/plugins/
COPY files/tedge/c8y_RemoteAccessConnect /etc/tedge/operations/c8y/
COPY files/tedge/c8y_RemoteAccessConnect /etc/tedge/operations/c8y/
COPY files/tedge/launch-remote-access.sh /usr/bin/
# Self update workflow
COPY files/tedge/software_update.toml /etc/tedge/operations/
COPY files/tedge/self_update.toml /etc/tedge/operations/
# Self update compatibility script for updating from images <= 20241126.1855
COPY files/tedge/self_update.sh /usr/bin/
# Container log_upload customer handler
COPY files/tedge/container-logs.sh /usr/bin/
COPY files/tedge/log_upload.toml /etc/tedge/operations/
COPY files/tedge/log_upload_container.toml /etc/tedge/operations/


ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=30000


# Control which mappers are running
# You can see the list of thin-edge.io services and the related env variable
# in the service definition under:
# * https://github.com/thin-edge/tedge-services/tree/main/services/s6-overlay/s6-rc.d
ENV SERVICE_MOSQUITTO=1

ENV SERVICE_TEDGE_MAPPER_AWS=0
ENV SERVICE_TEDGE_MAPPER_AZ=0
ENV SERVICE_TEDGE_MAPPER_C8Y=1
ENV SERVICE_TEDGE_MAPPER_COLLECTD=0

ENV SERVICE_TEDGE_AGENT=1
ENV SERVICE_C8Y_FIRMWARE_PLUGIN=0
ENV SERVICE_TEDGE_CONTAINER_PLUGIN=1


# Control thin-edge.io settings via env variables
ENV TEDGE_C8Y_PROXY_BIND_ADDRESS=0.0.0.0
ENV TEDGE_HTTP_BIND_ADDRESS=0.0.0.0
ENV TEDGE_RUN_LOCK_FILES=false
ENV TEDGE_MQTT_CLIENT_HOST=127.0.0.1
ENV TEDGE_HTTP_CLIENT_HOST=127.0.0.1
ENV TEDGE_C8Y_PROXY_CLIENT_HOST=127.0.0.1
# Store the agent information in the persistent data
# but don't share too much data as it can be destructive
ENV TEDGE_AGENT_STATE_PATH="$DATA_DIR/agent"
ENV TEDGE_LOGS_PATH="$DATA_DIR/logs"

EXPOSE 1883
EXPOSE 8000
EXPOSE 8001

USER "tedge"
# Allow users to re-use the container for one-off commands
# to ensure the thin-edge.io version remains the same
CMD [ "/init" ]
