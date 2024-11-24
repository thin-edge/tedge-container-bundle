FROM quay.io/containers/podman:v4.4
RUN systemctl enable podman.socket \
    # create systemd-tmpfiles config to create a symlink for docker to the podman socket
    # which allows using docker and docker compose without having to set the DOCKER_HOST variable
    # Source: podman-docker debian package
    && echo 'L+  %t/docker.sock   -    -    -     -   %t/podman/podman.sock' | tee /usr/lib/tmpfiles.d/podman-docker-socket.conf \
    && systemd-tmpfiles --create podman-docker.conf >/dev/null || true
ENTRYPOINT [ "/lib/systemd/systemd" ]