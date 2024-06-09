# tedge-container-bundle

This repo contains a container definition which configures all of the thin-edge.io components (including mosquitto) in a single container using the lightweight, container friendly init system, [s6-overlay](https://github.com/just-containers/s6-overlay).

[s6-overlay](https://github.com/just-containers/s6-overlay) is an init system which is desired to run multiple processes in a single container. It starts and supervises each service. Check out the [s6-overlay documentation](https://github.com/just-containers/s6-overlay) for further details.

This repository might be helpful if you are looking for a simple container deployment of thin-edge.io and don't want to spawn multiple containers, and your device does not have access to a Kubernetes instance like ([k3s](https://k3s.io/)).


**Features**

The **tedge-container-bundle** provides the following features:

* All components running in a single container (can be easier to manage and deploy)
* Allow setting device certificate from environment variables (or a volume)
* Provide mapper url (e.g. `c8y.url`) via environment variables
* Default plugin configurations (log and config)
* Run container as non-root user

## Getting Started

### Starting the container

The following tools are required to run the container:

* docker
* docker compose
* Optional: [just](https://github.com/casey/just) - used to run project tasks

After the project pre-requisites have been installed, you can start the container using the following steps:

1. Create a `.env` file containing the environment variables (see the [Providing the device certificate by environment variables](./README.md#providing-the-device-certificate-by-environment-variables) for details on how to provide the device certificate)

    ```sh
    # Device certificate (public/private)
    CERTPRIVATE=<base64_encoded_private_key>
    CERTPUBLIC=<base64_encoded_public_cert>

    # Which c8y instance you want to connect to
    TEDGE_C8Y_URL=example.cumulocity.com

    # You can turn specific services on/off via environment variables
    SERVICE_TEDGE_MAPPER_AWS=0
    SERVICE_TEDGE_MAPPER_AZ=0
    SERVICE_TEDGE_MAPPER_C8Y=1
    ```

2. Start the container (using docker compose)

    ```sh
    # using justfile task
    just start

    # Or using docker compose directly
    docker compose up --build
    ```

    Alternatively, you can start the container manually using the [justfile](https://github.com/casey/just) tasks (which call `docker run` instead of `docker compose`)

    ```sh
    just run-container
    ```

### Providing the device certificate by environment variables

The thin-edge.io certificate (both public and private keys) are provided to the container via environment variables.

The following environment variables are used to provide the certificate to the container's startup script `50_configure.sh` which is called by s6-overlay when the container starts up:

* `CERTPRIVATE` - Device certificate private key (base64 encoded)
* `CERTPUBLIC` - Device certificate public key (base64 encoded)

The environment variables are base64 encoded to avoid any shell quoting problems with whitespace any other unexpected characters. If you have the certificate files (public and private key), then you generate the encoded values using the following one-liners:

```sh
cat /etc/tedge/device-certs/tedge-private-key.pem | base64 | tr -d '\n' | xargs printf 'CERTPRIVATE=%s\n'
cat /etc/tedge/device-certs/tedge-certificate.pem | base64 | tr -d '\n' | xargs printf 'CERTPUBLIC=%s\n'
```

You can copy the output to your `.env` file (or set the environment variables yourself). An example of the `.env` file is shown below:

```sh
CERTPRIVATE=LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tsS0tCk1JR0hBZ0bBTUJNR0J5cUdTTTQ5QWdFR0NDcUdTTTQ5QXdFSEJHMHdhd0lCQVFRZ2lHcDE3eEZ5VlcvZXlka1kKaE4rM05McWtMM3dIK0d3c1BSZnFmZk1NQU9taFJBTkNBQVEyRVhSNnFnb3JNcldPUzQyNVlRT21DbFVsWWZHdwp6alRySnF6WnZjOTVkTzJnNUZEb1Z4ZFZSUuc5MWJNOFNvdDFVWnlZMklEaXpSUzBHZ3c0NgCBQUklWQVRFIEtFWS0tLS0tCd==
CERTPUBLIC=LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJ4RENDQVdxZ0F3SUJBZ0lVRlFOelh5eUNqTEpMQmxQVWRJeWUzNW9pUzZNd0NnWUlLb1pJemowRUSXcKU0RFY01Cb0dBMVVFQXd3VGRHVmtaMlZmWTI5dWRHRnBibVZ5WHpBd01URVNNQkFHQTFVRUNnd0pWR2hwYmlgpaR2RsTVJRd0VnWURVFMREF0VVpYTjBJRVJsZG1salpUQWVGdzB5TkRBMk1EWXdPREV3TXpaYUZ3MHlOVEEyCk1EWXdPREV3TXpaYU1FZ3hIREFhQmdkJBTU1FM1JsWkdkbFgyTnZiblJoYVc1bGNsOHdNREV4RWpBUUJnTlYKQkFvTUNWUm9hVzRnUldSblpURVVNQklHQTFVRUN3d0xWR1Z6NCRVpYWnBZMlV3V1RBVEJnY3Foa2pPUFFJQgpCZ2dxaGtqT1BRTUJCd05DQUFRMkVjZxZ29yTXJXT1M0MjVZUU9tQ2xVbFlmR3d6alRySnF6WnZjOTVkeTluCk8yZzVGRG9WeGRWUlFHOTFiTThTL3QxVVp5WTJJRGl6UlMwR2d3NDZvekl3TURBZEJnTlZIUTRFRmdRVUZRTnoKWHl5Q2pMSkxCbFBVZEl5ZTM1b2lTNk13ROSQpBREJGQWlFQSs1Z09Gem5LQ0lNSFVWODFJVzhMZkhFUzE0SXdGR3Y3Q2dzZjd2ZzNhck1DSUR1cGpsRjBFaHozCkx6d1VURySTR6YmRGbzc1WWVKODBXNXg1V1hlZzEzCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
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
