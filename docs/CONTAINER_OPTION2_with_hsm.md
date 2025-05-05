## Option 2: Container network with a HSM

**NOTES/DISCLAIMER**

* This instructions have not been fully tested, and are to be used as a starting guide only until it can be fully tested
* There are multiple ways to do this, the instructions just show one way on how to setup your device up
* Currently these instructions require the tedge-container-bundle-main image which uses the latest thin-edge.io version from the main branch (until the next official release, 1.5.0)

**When to use it?**

* Familiar with containers
* Basic understanding of container networking
* Familiar with HSMs (with a PKCS#11 interface)


### Initial setup

1. Pull the latest image

    ```sh
    docker pull ghcr.io/thin-edge/tedge-container-bundle-main
    ```

1. Create a docker volume which will be used to store the device certificate, and a volume for the tedge and mosquitto data

    ```sh
    export TEDGE_C8Y_URL=example.c8y.cumulocity.com

    docker network create tedge
    docker volume create device-certs
    docker volume create tedge
    ```

1. Add the public device certificate to the container

    You can do this multiple ways, but one way would be to encoded it to base64 and then write it to a named volume inside the container.

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        ghcr.io/thin-edge/tedge-container-bundle-main:latest \
        sh -c "echo \"$(base64 tedge-certificate.pem | tr -d '\n')\" | base64 -d > \$(tedge config get device.cert_path)"
    ```

1. Install the tedge-p11-server package from [Cloudsmith.io](https://cloudsmith.io/~thinedge/repos/tedge-main/packages/) on the host

    **Note:** Instructions on how to setup the [Cloudsmith.io](https://cloudsmith.io/~thinedge/repos/tedge-main/packages/) repository is shown on their website by clicking the "Set Me Up" button and choosing the appropriate repository type (e.g. Debian)

    ```sh
    sudo apt-get install tedge-p11-server
    ```

1. Configure the tedge-p11-server to which pkcs11 module it should use

    ```sh
    vim.tiny /etc/tedge/tedge.toml
    ```

    Below is an example of the settings which set both the pin for the HSM. Though if you're using a TPM 2.0 module, then you may need to use other settings (please consult the TPM 2.0 documentation for details)

    ```sh
    [device.cryptoki]
    module_path = "/usr/lib/aarch64-linux-gnu/opensc-pkcs11.so"
    socket_path = "/run/tedge-p11-server/tedge-p11-server.sock"
    pin = "123456"
    ```

    Note: The module path is generally different for each device (e.g. based on the CPU architecture), however it really depends on which PKCS#11 module is being used, as the library files are located in different locations depending on the Operating System / Distribution.

1. Restart the tedge-p11-server socket

    ```sh
    systemctl restart tedge-p11-server.socket
    ```

**Warning**

In order for the container to be able to read and write to the unix socket shared from the host (and created by **tedge-p11-server**), the User ID (UID) and Group ID of the `tedge` user/group on the host, must match the UID/GID used by the tedge user/group inside the container! This can either be done by changing the host's UID/GID to match those used by the container, or build the container image with your desired UID/GID from the host.

The UID/GID can be changed by running the following command and replacing the `NEW_UID` and `NEW_GID` with the desired values:

```sh
sudo usermod -u NEW_UID tedge
sudo groupmod -g NEW_GID tedge
```

### Start the container

```sh
docker run -d \
    --name tedge \
    --restart always \
    --add-host host.docker.internal:host-gateway \
    --network tedge \
    -p "127.0.0.1:1883:1883" \
    -p "127.0.0.1:8000:8000" \
    -p "127.0.0.1:8001:8001" \
    -v "device-certs:/etc/tedge/device-certs" \
    -v "tedge:/data/tedge" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -v /run/tedge-p11-server:/run/tedge-p11-server \
    -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
    -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
    -e TEDGE_MQTT_BRIDGE_BUILT_IN=true \
    -e TEDGE_DEVICE_CRYPTOKI_MODE=socket \
    -e TEDGE_DEVICE_CRYPTOKI_SOCKET_PATH=/run/tedge-p11-server/tedge-p11-server.sock \
    ghcr.io/thin-edge/tedge-container-bundle-main:latest
```

With this option, you can change the host port mapping in case it conflicts with any other services running on the host, e.g. other services which are already using the ports that thin-edge.io wants to use.

```sh
docker run -d \
    --name tedge \
    --restart always \
    --add-host host.docker.internal:host-gateway \
    --network tedge \
    -p "127.0.0.1:1884:1883" \
    -p "127.0.0.1:9000:8000" \
    -p "127.0.0.1:9001:8001" \
    -v "device-certs:/etc/tedge/device-certs" \
    -v "tedge:/data/tedge" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -v /run/tedge-p11-server:/run/tedge-p11-server \
    -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
    -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
    -e TEDGE_MQTT_BRIDGE_BUILT_IN=true \
    -e TEDGE_DEVICE_CRYPTOKI_MODE=socket \
    -e TEDGE_DEVICE_CRYPTOKI_SOCKET_PATH=/run/tedge-p11-server/tedge-p11-server.sock \
    ghcr.io/thin-edge/tedge-container-bundle-main:latest
```

### Subscribing to the MQTT broker

Assuming the container network is called `tedge`, then you can subscribe to the MQTT broker using the following command:

```sh
docker run --rm -it \
    --network tedge \
    -e TEDGE_MQTT_CLIENT_HOST=tedge \
    ghcr.io/thin-edge/tedge-container-bundle \
    tedge mqtt sub '#'
```

Or you can access the MQTT broker directly from the host using the port mappings:

```sh
mosquitto_sub -h 127.0.0.1 -p 1883 -t '#'

# or if you used another port
mosquitto_sub -h 127.0.0.1 -p 1884 -t '#'
```

## Alternative setups

### Starting tedge-container-bundle and bootstrap at runtime

For instances where you can't do the bootstrapping of the container before the container starts, you can use the following instructions which will configure and bootstrap the container after it has been started, though it will involve restarting the container after it is configured.

1. Create the required docker network and volumes

    ```sh
    docker network create tedge
    docker volume create device-certs
    docker volume create tedge
    ```

    If you have previously created the volumes, then it is recommended to delete them (to ensure a fresh installation) using the following commands:

    ```sh
    docker volume rm device-certs tedge
    ```

2. Start the container. Note: the container won't really work until you have manually bootstrapped it, so you will see a lot of error when looking at the logs)

    ```sh
    docker run -d \
        --name tedge \
        --restart always \
        --add-host host.docker.internal:host-gateway \
        --network tedge \
        -p "127.0.0.1:1883:1883" \
        -p "127.0.0.1:8000:8000" \
        -p "127.0.0.1:8001:8001" \
        -v "device-certs:/etc/tedge/device-certs" \
        -v "tedge:/data/tedge" \
        -v /var/run/docker.sock:/var/run/docker.sock:rw \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        ghcr.io/thin-edge/tedge-container-bundle:latest
    ```

3. Start interactive shell in the container (using the default user), and run the following commands

    ```sh
    docker exec -u tedge -it tedge sh
    ```

    Run the following commands to bootstrap your container:

    ```sh
    tedge cert create --device-id "mydevice0001"
    tedge config set c8y.url thin-edge-io.eu-latest.cumulocity.com
    tedge cert upload c8y

    tedge reconnect c8y
    ```

4. The device should now have been registered with Cumulocity and you can also check the container logs (from outside of the container):

    ```sh
    docker logs -f tedge
    ```
