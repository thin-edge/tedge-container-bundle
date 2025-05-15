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

[Option 2a (Self-Signed Certificates): Container network (Recommended)](./docs/CONTAINER_OPTION2.md)

[Option 2b (Cumulocity Certificate Authority Preview): Container network (Recommended)](./docs/CONTAINER_OPTION2_with_ca.md)


### Settings

All of the thin-edge.io settings can be customized via environment variables which can be added via the `-e KEY=VALUE` to the `docker run` command:

```sh
TEDGE_C8Y_OPERATIONS_AUTO_LOG_UPLOAD=always
```

### Development

#### Testing

The system tests are writing using the [RobotFramework](https://robotframework.org/) with some custom thin-edge.io libraries. Generally the test framework will spin up a new container engine environment (defined by the `TEST_IMAGE` variable). In the test itself, a new instance of the **tedge-container-bundle** will be created which the test then uses to check the specified functionality. Using this setup does bring a but if complexity into the setup, however it is necessary to ensure that the **tedge-container-bundle** can be tested against multiple container engine environments (e.g. docker, podman and different versions of each), whilst it also provides a test environment which does not pollute your host's container engine environment.

The following tools are required to run the tests:

* docker
* [docker-buildx-plugin](https://github.com/docker/buildx)
* [go-c8y-cli](https://goc8ycli.netlify.app/)
* Optional: [just](https://github.com/casey/just) - used to run project tasks
* python >= 3.9

After the project pre-requisites have been installed, you can start the container using the following steps:

1. First run only: Activate your Cumulocity session using [go-c8y-cli](https://goc8ycli.netlify.app/docs/gettingstarted/#creating-a-new-session)

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

2. Create a `.env` file containing the environment variables used for testing

    ```sh
    just init-dotenv
    ```

    **Note** This will write your current go-c8y-cli's session credentials to the `.env` file, so you don't need to use `set-session` every time.

3. Initialize the docker setup and install the python virtual environment

    ```sh
    just build-setup
    just venv
    ```

4. Build test images

    ```sh
    just build-test
    ```

5. Run system tests

    ```sh
    just test
    ```

#### Cumulocity Certificate Authority (Preview)

Note: These instructions use the Cumulocity certificate-authority feature and a UI change (pre-filling registration via a URL) which might not be deployed on your tenant.

**For Users**

See these [Instructions](./docs/CONTAINER_OPTION2_with_ca.md) which will detail how to start a tedge-container-bundle project using the new Cumulocity certificate-authority feature and a pre-built image.

**For Developers with go-c8y-cli**

1. Active your Cumulocity session using go-c8y-cli

    ```sh
    set-session
    ```

2. Start the local image (running in the foreground)

    ```sh
    docker compose up --build
    ```

3. Click on the registration url to be redirected to the Cumulocity URL in your browser and confirm the registration


**Notes**

You can change the default device enrollment by setting the following environment variables on the container. 

```sh
C8Y_DOMAIN=example-demo.eu-latest.cumulocity.com
DEVICE_ID=tedge_mydevice001
DEVICE_ONE_TIME_PASSWORD=<max_32_chars>
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

## Contributions

#### PR Submissions

Contributions are welcomed, but please consider the following

* Does the change make sense for other users? If the answer is no, then maybe you should be just pulling in the `tedge-container-bundle` into your own Dockerfile using `FROM ghcr.io/thin-edge/tedge-container-bundle:<tag>`

* State the motivation of the change

* Write a system test (under `./tests`) and ensure all tests are passing (though the CI will also run this on the PR directly)

Finally, before submitting a PR you should run the following locally to ensure everything is formatted correct and there are no linting errors/warnings!

```sh
just venv
just lint
just format
```
