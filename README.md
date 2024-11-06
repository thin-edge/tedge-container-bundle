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

### Choose a setup

[Option 1: On Host Network](./docs/CONTAINER_OPTION1.md)

[Option 2: Container network (Recommended)](./docs/CONTAINER_OPTION2.md)


### Settings

All of the thin-edge.io settings can be customized via environment variables which can be added via the `-e KEY=VALUE` to the `docker run` command:

```sh
TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always
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
    # device id to use for the certificate
    DEVICE_ID=demo01

    # Which c8y instance you want to connect to
    TEDGE_C8Y_URL=example.cumulocity.com

    # You can turn specific services on/off via environment variables
    SERVICE_TEDGE_MAPPER_AWS=0
    SERVICE_TEDGE_MAPPER_AZ=0
    SERVICE_TEDGE_MAPPER_C8Y=1

    # Other settings
    TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always
    ```

2. Activate your Cumulocity session using go-c8y-cli

    ```sh
    set-session
    ```

    **Note**

    Your go-c8y-cli session profile needs to have the following setting set (and you will have to run `set-session` again afterwards):

    ```sh
    c8y settings update session.alwaysIncludePassword true

    # Then re-activate the session
    set-session
    ```

3. Init the device certificate (stored under `./device-cert) and upload it to Cumulocity IoT

    ```sh
    just init
    ```

4. Start the container (using docker compose)

    ```sh
    # using the justfile task
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
