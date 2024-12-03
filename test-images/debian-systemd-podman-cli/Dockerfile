FROM ghcr.io/thin-edge/tedge-demo-main-systemd:latest
ARG TARGETPLATFORM

# Allow ssh connection from container network
RUN sed -i 's|^ListenAddress 127.0.0.1|ListenAddress 0.0.0.0|g' /etc/ssh/sshd_config

# Disable tedge-container-plugin running on the host
RUN systemctl disable tedge-container-plugin

RUN tedge config unset c8y.proxy.client.host \
    && tedge config unset mqtt.client.host \
    && tedge config unset http.client.host
