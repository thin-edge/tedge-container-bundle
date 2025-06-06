## Features

### Self update

Self updates can be done by using `container` type.

1. Create a repository item

    ```sh
    c8y software create \
        --name tedge \
        --softwareType container
    ```

2. Add a new version

    ```sh
    c8y software versions create \
        --software tedge \
        --url " " \
        --version "ghcr.io/thin-edge/tedge-container-bundle:20241201.0920"
    ```

3. Create an operation to install software (go-c8y-cli >= v2.45.0)

    ```sh
    c8y software versions install \
        --device "subdevice01" \
        --action install \
        --software tedge \
        --version "ghcr.io/thin-edge/tedge-container-bundle:20241201.0920"
    ```

    Or if you haven't created a `tedge` software repository item, then you can install software without it, by specifying all of the required fields (including a empty space for the `--url` flag.)

    ```sh
    c8y software versions install \
        --device "subdevice01" \
        --action install \
        --software tedge \
        --softwareType container \
        --url " " \
        --version "ghcr.io/thin-edge/tedge-container-bundle:20241201.0920"
    ```


### SSH Access

**When to use it?**

* Need to maintain the host operating system

**Pre-requisites**

* container is attached to the bridge network
* **docker only** container has an extra host configured for the docker network (e.g. `--add-host=host.docker.internal:host-gateway`)
* ssh daemon has a listener on the container bridge network (e.g. typically `172.17.0.1` for docker, though you can check by running `ifconfig` and getting the ipv4 address of the docker or podman network adapter)
* Either your ssh keys have been added to the device, or allows password authentication

After the pre-requisites are met, you can easily access your device using the following steps:

1. Create a Cloud Remote Access PASSTHROUGH configuration for the device

    **docker**

    ```sh
    c8y remoteaccess configurations create-passthrough \
        --device device01 \
        --hostname host.docker.internal \
        --port 22 \
        --name device-host
    ```

    **podman**

    ```sh
    c8y remoteaccess configurations create-passthrough \
        --device device01 \
        --hostname host.containers.internal \
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

**Limitations**

If you create a "SSH" remote access configuration item, then you MUST use the docker's gateway IP address, e.g. `172.17.0.1` instead of the `host.docker.internal` address. If you don't use the IP address, then you will get the following error in the WebSSH client (in the UI):

```sh
host.docker.internal: Name does not resolve
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
