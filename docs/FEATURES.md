## Features

### Self update

1. Create a repository item

    ```sh
    c8y software create \
        --name tedge \
        --softwareType self
    ```

2. Add a new version

    ```sh
    c8y software versions create \
        --software tedge \
        --url " " \
        --version "ghcr.io/thin-edge/tedge-container-bundle:20240929.1503"
    ```

    ```sh
    c8y software versions create \
        --software tedge \
        --url " " \
        --version "ghcr.io/thin-edge/tedge-container-bundle:latest"
    ```

3. Create an operation to install software

    ```sh
    c8y software versions install \
        --action install \
        --software tedge \
        --version "ghcr.io/thin-edge/tedge-container-bundle:latest"
    ```

    ```sh
    c8y software versions install \
        --device "subdevice01" \
        --action install \
        --software tedge \
        --data softwareType=self \
        --url " " \
        --version "ghcr.io/thin-edge/tedge-container-bundle:latest"
    ```


### SSH Access

**When to use it?**

* Need to maintain the host operating system

**Pre-requisites**

* container is attached to the bridge network
* container has an extra host configured for the docker network (e.g. `--add-host=host.docker.internal:host-gateway`)
* ssh daemon has a listener on the container bridge network (e.g. typically `172.17.0.1`)
* Either your ssh keys have been added to the device, or allows password authentication

After the pre-requisites are met, you can easily access your device using the following steps:

1. Create a Cloud Remote Access PASSTHROUGH configuration for the device

    ```sh
    c8y remoteaccess configurations create-passthrough \
        --device device01 \
        --hostname host.docker.internal \
        --port 22 \
        --name device-host
    ```

2. Connect to the device using ssh

    ```sh
    c8y remoteaccess connect ssh \
        --device device01 \
        --user root \
        --configuration device-host
    ```


### SSH daemon configuration

The ssh daemon must be listening on the docker network adapter to enable an SSH connection.

1. Edit the ssh daemon configuration add check if there is a listener configured for the default docker network

    ```sh
    docker network inspect bridge
    ```

    **file: /etc/ssh/sshd_config**

    ```
    #Port 22
    #AddressFamily any
    #ListenAddress 0.0.0.0
    ListenAddress 127.0.0.1
    ListenAddress 172.17.0.1
    #ListenAddress ::
    ```

2. Reload the ssh service (if a change was made)

    ```sh
    systemctl reload ssh
    ```
