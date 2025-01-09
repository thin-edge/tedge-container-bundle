## Option 2: Container network

**When to use it?**

* Familiar with containers
* Basic understanding of container networking


### Initial setup

1. Pull the latest image

    ```sh
    docker pull ghcr.io/thin-edge/tedge-container-bundle
    ```

2. Create a docker volume which will be used to store the device certificate, and a volume for the tedge and mosquitto data

    ```sh
    export TEDGE_C8Y_URL=example.c8y.cumulocity.com

    docker network create tedge
    docker volume create device-certs
    docker volume create tedge
    ```

3. Create a new device certificate

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        ghcr.io/thin-edge/tedge-container-bundle:latest \
        tedge cert create --device-id "<mydeviceid>"
    ```

4. Upload the device certificate to Cumulocity IoT

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        ghcr.io/thin-edge/tedge-container-bundle:latest \
        tedge cert upload c8y
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
    -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
    -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
    ghcr.io/thin-edge/tedge-container-bundle:latest
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
    -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
    -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
    ghcr.io/thin-edge/tedge-container-bundle:latest
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
    docker volume rm device-certs
    docker volume rm tedge
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

    # reboot the container, or alternatively you can use docker cli for this
    reboot
    ```

4. The device should now have been registered with Cumulocity and you can also check the container logs (from outside of the container):

    ```sh
    docker logs -f tedge
    ```
