## Option 2: Container network and using Cumulocity Certificate-Authority

NOTE: These instructions use the Cumulocity Certificate Authority feature which is still in Public Preview. You can read information about the feature from the [thin-edge.io documentation](https://thin-edge.github.io/thin-edge.io/operate/c8y/connect/#cumulocity-certificate-authority) which also includes a link to the underlying Cumulocity docs.

**When to use it?**

* Familiar with containers
* Basic understanding of container networking
* You have the Cumulocity certificate-authority feature activated in your tenant

## Getting Started

### Option 1: Using docker run

1. Pull the latest image

    ```sh
    docker pull ghcr.io/thin-edge/tedge-container-bundle
    ```

1. Create a docker volume which will be used to store the device certificate, and a volume for the tedge and mosquitto data

    ```sh
    docker network create tedge
    docker volume create device-certs
    docker volume create tedge
    ```

1. Set some environment variable based on the Cumulocity instance you wish to connect to, and the device id and one-time password (which is used when requesting the first device certificate)

    ```sh
    export TEDGE_C8Y_URL="example-demo.eu-latest.cumulocity.com"
    export DEVICE_ID="tedge_abcdef"
    export DEVICE_ONE_TIME_PASSWORD="<<code_max_32_chars>>"
    ```

1. Start the container

    ```sh
    docker run -d \
        --name tedge \
        --restart always \
        --add-host host.docker.internal:host-gateway \
        --network tedge \
        -p "127.0.0.1:1883:1883" \
        -p "127.0.0.1:8000:8000" \
        -p "127.0.0.1:8001:8001" \
        -v device-certs:/etc/tedge/device-certs \
        -v tedge:/data/tedge \
        -v /var/run/docker.sock:/var/run/docker.sock:rw \
        -e CA=c8y \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        -e "DEVICE_ID=${DEVICE_ID}" \
        -e "DEVICE_ONE_TIME_PASSWORD=${DEVICE_ONE_TIME_PASSWORD}" \
        -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
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
        -v device-certs:/etc/tedge/device-certs \
        -v tedge:/data/tedge \
        -v /var/run/docker.sock:/var/run/docker.sock:rw \
        -e CA=c8y \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        -e "DEVICE_ID=${DEVICE_ID}" \
        -e "DEVICE_ONE_TIME_PASSWORD=${DEVICE_ONE_TIME_PASSWORD}" \
        -e "TEDGE_C8Y_URL=${C8Y_DOMAIN:-$TEDGE_C8Y_URL}" \
        ghcr.io/thin-edge/tedge-container-bundle:latest
    ```

1. Open the Cumulocity Device Management application and register the device as per the [thin-edge.io documentation](https://thin-edge.github.io/thin-edge.io/operate/c8y/connect/#cumulocity-certificate-authority) and using the same device-id and one-time password defined in the previous steps.

    Alternatively, can print the following URL on the same console where you previously set the environment variables, and then ctrl-click the URL to open up the URL in your browser.

    ```sh
    echo
    echo "Register device by clicking on the following URL"
    echo
    echo "  https://${TEDGE_C8Y_URL}/apps/devicemanagement/index.html#/deviceregistration?externalId=${DEVICE_ID}&one-time-password=${DEVICE_ONE_TIME_PASSWORD}"
    echo
    ```

### Option 2: Using docker compose

1. In a shell, create a new folder and change directory into it. The name of the folder will be your docker compose project name

1. Create a `.env` file with the following contents

    ```sh
    TEDGE_C8Y_URL="example-demo.eu-latest.cumulocity.com"
    DEVICE_ID="tedge_abcdef"
    DEVICE_ONE_TIME_PASSWORD="<<code_max_32_chars>>"

    # any other custom thin-edge.io configuration that you want
    TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always
    ```

1. Create a `docker-compose.yaml` file with the following contents

    ```yaml
    services:
      tedge:
        image: ghcr.io/thin-edge/tedge-container-bundle
        restart: always
          env_file:
            - .env
        ports:
          - 127.0.0.1:1883:1883
          - 127.0.0.1:8000:8000
          - 127.0.0.1:8001:8001
        tmpfs:
          - /tmp
        volumes:
          - device-certs:/etc/tedge/device-certs
          - tedge:/data/tedge
          # Enable docker from docker
          - /var/run/docker.sock:/var/run/docker.sock:rw

    volumes:
      device-certs:
      tedge:
    ```

1. Start the container using docker compose

    ```sh
    docker compose up -d
    ```

1. Open the Cumulocity Device Management application and register the device as per the [thin-edge.io documentation](https://thin-edge.github.io/thin-edge.io/operate/c8y/connect/#cumulocity-certificate-authority) and using the same device-id and one-time password defined in the previous steps.

    Alternatively, can print the following URL on the same console where you previously set the environment variables, and then ctrl-click the URL to open up the URL in your browser.

    ```sh
    # load env variables from the .env file you created earlier
    set -a; . .env; set +a
    echo "Register device by clicking on the following URL"
    echo
    echo "  https://${TEDGE_C8Y_URL}/apps/devicemanagement/index.html#/deviceregistration?externalId=${DEVICE_ID}&one-time-password=${DEVICE_ONE_TIME_PASSWORD}"
    echo
    ```

## Using the tedge-container-bundle

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
