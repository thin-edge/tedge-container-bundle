## Option 3: Running thin-edge.io in an isolated container network

**When to use it?**

* Comfortable with container and networking
* Need full control over the network to control access from other container
* Deploying all applications in containers
* Want to run multiple instances


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

Assuming the container network is called `tedge`, then run:

```sh
docker run -d \
    --name tedge \
    --network tedge \
    --restart always \
    --add-host=host.docker.internal:host-gateway \
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
