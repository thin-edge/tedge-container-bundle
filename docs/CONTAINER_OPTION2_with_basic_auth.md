## Option 2: Container network and using Cumulocity Basic Auth

**When to use it?**

* Familiar with containers
* Basic understanding of container networking
* You can't use certificate based auth for reason

## Getting Started


### Option 1: Using docker run

1. Pull the latest image

    ```sh
    docker pull ghcr.io/thin-edge/tedge-container-bundle
    ```

1. Create Cumulocity basic auth credentials for your new device. For convenience, you can use go-c8y-cli to do this

    ```sh
    c8y deviceregistration register-basic --id tedge_abcdef
    ```

    Take note of the `username` and `password` fields in the output, as you'll need these in next step.

1. Set some environment variable on the console based on the Cumulocity instance you wish to connect to, and the device id

    ```sh
    export TEDGE_C8Y_URL="example-demo.eu-latest.cumulocity.com"
    export DEVICE_ID="tedge_abcdef"
    export C8Y_DEVICE_USER="t12345/device_${DEVICE_ID}"
    export C8Y_DEVICE_PASSWORD='<<code_max_32_chars>>'
    ```

    **Notes**

    * The username must be in the form of `{tenant}/device_{name}`
    * The password should use single quotes to avoid problems if it contains a `$` character (as a shell would other think it is a variable reference)

1. Create a docker volume which will be used to store the device credentials, and a volume for the tedge and mosquitto data

    ```sh
    docker network create tedge
    docker volume create device-creds
    docker volume create tedge
    ```

3. Create a new device credentials

    ```sh
    docker run --rm -it \
        -v "device-creds:/etc/tedge/credentials" \
        -e "TEDGE_C8Y_CREDENTIALS_PATH=/etc/tedge/credentials/credentials.toml" \
        ghcr.io/thin-edge/tedge-container-bundle:latest \
        /usr/bin/set-c8y-basic-auth.sh "$C8Y_DEVICE_USER" "$C8Y_DEVICE_PASSWORD"
    ```

    Alternatively, you can set the Cumulocity device username and password using environment variables, however be aware that they could then be read by anyone with access to the container engine.

    ```sh
    -e "C8Y_DEVICE_USER=$C8Y_DEVICE_USER" \
    -e "C8Y_DEVICE_PASSWORD=$C8Y_DEVICE_PASSWORD" \
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
        -v device-creds:/etc/tedge/credentials \
        -v tedge:/data/tedge \
        -v /var/run/docker.sock:/var/run/docker.sock:rw \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        -e "DEVICE_ID=${DEVICE_ID}" \
        -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
        -e "TEDGE_C8Y_AUTH_METHOD=auto" \
        -e "TEDGE_C8Y_CREDENTIALS_PATH=/etc/tedge/credentials/credentials.toml" \
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
        -v device-creds:/etc/tedge/credentials \
        -v tedge:/data/tedge \
        -v /var/run/docker.sock:/var/run/docker.sock:rw \
        -e TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always \
        -e "DEVICE_ID=${DEVICE_ID}" \
        -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
        -e "TEDGE_C8Y_AUTH_METHOD=auto" \
        -e "TEDGE_C8Y_CREDENTIALS_PATH=/etc/tedge/credentials/credentials.toml" \
        ghcr.io/thin-edge/tedge-container-bundle:latest
    ```


### Option 2: Using docker compose

Note: This docker compose example uses environment variable to set the basic auth. Ideally you would not set the credentials this ways as it makes them readable to anyone whom has access to the container engine.

1. In a shell, create a new folder and change directory into it. The name of the folder will be your docker compose project name

1. Create a `.env` file with the following contents

    ```sh
    TEDGE_C8Y_URL="example-demo.eu-latest.cumulocity.com"
    DEVICE_ID="tedge_abcdef"
    C8Y_DEVICE_USER="t12345/device_tedge_abcdef"
    C8Y_DEVICE_PASSWORD='<<code_max_32_chars>>'

    # any other custom thin-edge.io configuration that you want
    TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always
    ```

    **Notes**

    * The username must be in the form of `{tenant}/device_{name}`
    * The password should use single quotes to avoid problems if it contains a `$` character (as a shell would other think it is a variable reference)

1. Create a `docker-compose.yaml` file with the following contents

    ```yaml
    services:
      tedge:
        image: ghcr.io/thin-edge/tedge-container-bundle
        restart: always
        environment:
          - TEDGE_C8Y_AUTH_METHOD=auto
          - TEDGE_C8Y_CREDENTIALS_PATH=/etc/tedge/credentials/credentials.toml
        env_file:
          - .env
        ports:
         - 127.0.0.1:1883:1883
         - 127.0.0.1:8000:8000
         - 127.0.0.1:8001:8001
        # When using docker, add access to the host
        # if you want to be able to ssh into the host from the container
        extra_hosts:
          - host.docker.internal:host-gateway
        tmpfs:
          - /tmp
        volumes:
          - device-creds:/etc/tedge/credentials
          - tedge:/data/tedge
          # Enable docker from docker
          - /var/run/docker.sock:/var/run/docker.sock:rw

    volumes:
      device-creds:
      tedge:
    ```

1. Start the container using docker compose

    ```sh
    docker compose up -d
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
