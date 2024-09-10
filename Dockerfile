ARG TEDGE_TAG=1.2.1-134-ge4ff79b
# thin-edge.io base image name: tedge, tedge-main
ARG TEDGE_IMAGE=tedge-main
FROM ghcr.io/thin-edge/${TEDGE_IMAGE}:${TEDGE_TAG}
ARG TARGETPLATFORM
ARG S6_OVERLAY_VERSION=3.2.0.0

USER root

# Notes: ca-certificates is required for the initial connection with c8y, otherwise the c8y cert is not trusted
# to test out the connection. But this is only needed for the initial connection, so it seems unnecessary
RUN apk update \
    && apk add --no-cache \
        ca-certificates \
        mosquitto \
        bash \
        curl \
        # GNU sed (to provide the unbuffered streaming option used in the log parsing)
        sed

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
    && tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz

# Add custom service definitions (e.g. s6-overlay) and community plugins
RUN rm -f /etc/tedge/system.toml
RUN wget -O - https://thin-edge.io/install-services.sh | sh -s -- s6_overlay \
    && apk add --no-cache \
        c8y-command-plugin \
        tedge-apk-plugin

# Set permissions of all files under /etc/tedge
# TODO: Can thin-edge.io set permissions during installation?
RUN chown -R tedge:tedge /etc/tedge

# Custom init. scripts - e.g. write env variables data to files
COPY cont-init.d/*  /etc/cont-init.d/

# mosquitto configuration
RUN mkdir -p /mosquitto/data/ \
    && chown -R tedge:tedge /mosquitto/data/
COPY files/mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf

# Add custom thin-edge.io configuration (e.g. plugin config)
COPY files/tedge/tedge.toml /etc/tedge/
COPY files/tedge/plugins/*.toml /etc/tedge/plugins/


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


# Control thin-edge.io settings via env variables
ENV TEDGE_C8Y_PROXY_BIND_ADDRESS=0.0.0.0
ENV TEDGE_HTTP_BIND_ADDRESS=0.0.0.0
ENV TEDGE_RUN_LOCK_FILES=false
ENV TEDGE_MQTT_CLIENT_HOST=127.0.0.1
ENV TEDGE_HTTP_CLIENT_HOST=127.0.0.1
ENV TEDGE_C8Y_PROXY_CLIENT_HOST=127.0.0.1

# Allow mounting certificate files by volume
VOLUME [ "/etc/tedge/device-certs" ]

USER "tedge"
# Allow users to re-use the container for one-off commands
# to ensure the thin-edge.io version remains the same
CMD [ "/init" ]
