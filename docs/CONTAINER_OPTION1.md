## Deployment Type: Containers

## Option 1: Running thin-edge.io to the the host network

**When to use it?**

* Unfamiliar with container environments
* Running on a device where docker isn't configured properly and the networking is broken
* Just want something working quickly to try things out (and just run it like a normal applications)


### Initial setup

1. Create a docker volume which will be used to store the device certificate, and a volume for the tedge and mosquitto data

    ```sh
    export TEDGE_C8Y_URL=example.c8y.cumulocity.com

    docker volume create device-certs
    docker volume create tedge
    ```

2. Create a new device certificate

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        ghcr.io/thin-edge/tedge-container-bundle \
        tedge cert create --device-id "<mydeviceid>"
    ```

3. Upload the device certificate to Cumulocity IoT

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        ghcr.io/thin-edge/tedge-container-bundle \
        tedge cert upload c8y
    ```

### Start the container

```sh
docker run -d \
    --name tedge \
    --restart always \
    --network host \
    -v "device-certs:/etc/tedge/device-certs" \
    -v "tedge:/data/tedge" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
    ghcr.io/thin-edge/tedge-container-bundle
```

### Subscribing to the MQTT broker

```sh
docker run --rm -it --network host \
    ghcr.io/thin-edge/tedge-container-bundle \
    tedge mqtt sub '#'
```
