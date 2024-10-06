## Deployment Type: Containers

## Option 2: Accessible from outside

**When to use it?**

* Familiar with containers
* Basic understanding of container networking


### Initial setup

1. Create a docker volume which will be used to store the device certificate, and a volume for the tedge and mosquitto data

    ```sh
    export TEDGE_C8Y_URL=example.c8y.cumulocity.com

    docker network create tedge
    docker volume create device-certs
    docker volume create tedge
    ```

2. Create a new device certificate

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        ghcr.io/thin-edge/tedge-container-bundle:latest \
        tedge cert create --device-id "<mydeviceid>"
    ```

3. Upload the device certificate to Cumulocity IoT

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

Assuming the container network is called `tedge`, then run:

```sh
docker run --rm -it --network tedge \
    -e TEDGE_MQTT_CLIENT_HOST=tedge \
    ghcr.io/thin-edge/tedge-container-bundle \
    tedge mqtt sub '#'
```

Or you can access the MQTT broker directly from the host using the port mappings:

```sh
mosquitto_sub -h 127.0.0.1 -p 1883 -t '#'
```
