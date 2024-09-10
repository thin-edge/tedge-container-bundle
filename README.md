# tedge-container-bundle

This project contains a container definition which configures all of the thin-edge.io components (including mosquitto) in a single container using the lightweight, container friendly init system, [s6-overlay](https://github.com/just-containers/s6-overlay).

[s6-overlay](https://github.com/just-containers/s6-overlay) is an init system which is designed to run multiple processes in a single container. It starts and supervises each service, in addition to supporting startup/initialization scripts. For more details about s6-overlay, check out the [s6-overlay documentation](https://github.com/just-containers/s6-overlay).

This repository might be helpful if you are looking for a simple container deployment of thin-edge.io and don't want to spawn multiple containers, and your device does not have access to a Kubernetes instance like ([k3s](https://k3s.io/)).


**Features**

The **tedge-container-bundle** provides the following features:

* All components running in a single container (can be easier to manage and deploy)
* Allow setting device certificate from environment variables (or a volume)
* Provide mapper url (e.g. `c8y.url`) via environment variables
* Default plugin configurations (log and config)
* Run container as non-root user

## Getting Started

### Pre-requisites

The following are required in order to deploy the container

* docker
* docker compose

### Step 1: Create a device certificate inside a named volume

Before you can start the containers, you need to create a device certificate inside a named volume.

1. Create a docker volume which will be used to store the device certificate

    ```sh
    docker volume create device-certs
    ```

2. Set the Cumulocity IoT variable (to make it easier to copy/paste the remaining instructions)

    ```sh
    TEDGE_C8Y_URL="${C8Y_DOMAIN}"
    ```

3. Create a new device certificate

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
        ghcr.io/thin-edge/tedge-container-bundle:latest tedge cert create --device-id "<mydeviceid>"
    ```

4. Upload the device certificate to Cumulocity IoT

    ```sh
    docker run --rm -it \
        -v "device-certs:/etc/tedge/device-certs" \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        ghcr.io/thin-edge/tedge-container-bundle:latest tedge cert upload c8y
    ```

    If you are having problems with the docker network, you can try to use the host network and explicitly set a DNS address:

    ```sh
    docker run --rm -it --dns 8.8.8.8 --network host \
    -v "device-certs:/etc/tedge/device-certs" \
    -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
    ghcr.io/thin-edge/tedge-container-bundle:latest tedge cert upload c8y
    ```

    **Tip**

    If you don't want to be prompted for the Cumulocity IoT Username and Password (required to upload the certificate), then you can provide them via the following environment variables:

    ```sh
    docker run --rm -it --dns 8.8.8.8 --network host \
    -v "device-certs:/etc/tedge/device-certs" \
    -e "TEDGE_C8Y_URL=${TEDGE_C8Y_URL}" \
    -e "C8Y_USER=$C8Y_USER" \
    -e "C8Y_PASSWORD=$C8Y_PASSWORD" \
    ghcr.io/thin-edge/tedge-container-bundle:latest tedge cert upload c8y
    ```

### Step 2: Start thin-edge.io

Once the device certificate has been created inside the named volume, the same volume can be used when starting the container.

```sh
docker run --rm -it --dns 8.8.8.8 --network host \
    -v "device-certs:/etc/tedge/device-certs" \
    -e "TEDGE_C8Y_URL=$C8Y_DOMAIN" \
    ghcr.io/thin-edge/tedge-container-bundle:latest
```

The `TEDGE_C8Y_URL` env variable is used to set the target Cumulocity IoT so that thin-edge.io knows where to connect to.

All of the thin-edge.io settings can be customized via environment variables, which can be useful if you want to change the port numbers like in the following example:

```sh
docker run --rm -it --dns 8.8.8.8 --network host \
    -d \
    -v "device-certs:/etc/tedge/device-certs" \
    -e TEDGE_C8Y_PROXY_BIND_PORT=9001 \
    -e TEDGE_C8Y_PROXY_CLIENT_PORT=9001 \
    -e TEDGE_MQTT_BIND_PORT=1884 \
    -e TEDGE_MQTT_CLIENT_PORT=1884 \
    -e TEDGE_HTTP_BIND_PORT=9000 \
    -e TEDGE_HTTP_CLIENT_PORT=9000 \
    -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
    ghcr.io/thin-edge/tedge-container-bundle:latest
```

### Development

#### Starting the container

The following tools are required to run the container:

* docker
* docker compose
* Optional: [just](https://github.com/casey/just) - used to run project tasks

After the project pre-requisites have been installed, you can start the container using the following steps:

1. Create a `.env` file containing the environment variables (see the [Providing the device certificate by environment variables](./README.md#providing-the-device-certificate-by-environment-variables) for details on how to provide the device certificate)

    ```sh
    # Which c8y instance you want to connect to
    TEDGE_C8Y_URL=example.cumulocity.com

    # You can turn specific services on/off via environment variables
    SERVICE_TEDGE_MAPPER_AWS=0
    SERVICE_TEDGE_MAPPER_AZ=0
    SERVICE_TEDGE_MAPPER_C8Y=1
    ```

2. Init the device certificate (stored under `./device-cert)

    ```sh
    just init "$DEVICE_ID"
    ```

3. Upload the device certificate to Cumulocity IoT

    ```sh
    just upload
    ```

4. Start the container (using docker compose)

    ```sh
    # using justfile task
    just start

    # Or using docker compose directly
    docker compose up --build
    ```


## Project structure

|Directory|Description|
|---|--|
|cont-init.d/|Initialization scripts which are run before the services are started|
|files/tedge/plugins/|Default thin-edge.io plugin configuration files to control defaults such as log and configuration management settings|
|files/tedge/tedge.toml|File based thin-edge.io default settings. An alternative, if you don't want to set thin-edge.io setting via environment settings|
|files/mosquitto/mosquitto.conf|Default mosquitto settings to control logging and data persistence|

## Notes on s6-overlay

* Both the initialization scripts and services have access to the container's environment variables, which makes it much easier to configure the components.
* Standard Output and Standard Error are redirected to the PID 1 so that the log messages are visible from all services
* Run services under the container `USER`
