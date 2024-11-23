FROM ghcr.io/thin-edge/tedge-demo-main-systemd:latest
ARG TARGETPLATFORM

RUN tedge config unset c8y.proxy.client.host \
    && tedge config unset mqtt.client.host \
    && tedge config unset http.client.host

#
# Copy artifacts used to test against
#
COPY output/*.apk /tmp/
RUN case ${TARGETPLATFORM} in \
        "linux/386")  PKG_ARCH=linux_386  ;; \
        "linux/amd64")  PKG_ARCH=linux_amd64  ;; \
        "linux/arm64")  PKG_ARCH=linux_arm64  ;; \
        "linux/arm/v6")  PKG_ARCH=linux_armv6  ;; \
        "linux/arm/v7")  PKG_ARCH=linux_armv7  ;; \
        *) echo "Unsupported target platform: TARGETPLATFORM=$TARGETPLATFORM"; exit 1 ;; \
    esac \
    && mkdir -p /build \
    && cp /tmp/*${PKG_ARCH}*.apk /build/ \
    && rm -f /tmp/*.apk

# Script is called on test setup
COPY ./test-images/common/container-bundle.sh /usr/bin/
