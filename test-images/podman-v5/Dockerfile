FROM quay.io/containers/podman:v5.7
RUN systemctl enable podman.socket \
    && echo "enable podman.socket" > /usr/lib/systemd/system-preset/95-podman.preset \
    # create systemd-tmpfiles config to create a symlink for docker to the podman socket
    # which allows using docker and docker compose without having to set the DOCKER_HOST variable
    # Source: podman-docker debian package
    && echo 'L+  %t/docker.sock   -    -    -     -   %t/podman/podman.sock' | tee /usr/lib/tmpfiles.d/podman-docker-socket.conf \
    && systemd-tmpfiles --create podman-docker-socket.conf >/dev/null || true \
    # disable first boot otherwise the Fedora 43 hangs on startup which prevents other services from starting
    && rm -f /usr/lib/systemd/system/sysinit.target.wants/systemd-firstboot.service
ENTRYPOINT [ "/lib/systemd/systemd" ]