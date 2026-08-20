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


### Self update from an image file

If the device has no access to a container registry, the image can be uploaded to Cumulocity
as a binary and installed from there. The archive is created with `docker save` (or
`podman save`) and must contain the image under the same reference that is used as the
software version, otherwise the update is rejected.

1. Pull the image on a machine which does have registry access

    The platform (`PLATFORM`) must match the device, as the archive only holds the platform that was
    pulled.

    ```sh
    PLATFORM="linux/arm64"
    VERSION="20241201.0920"
    docker pull --platform "$PLATFORM" ghcr.io/thin-edge/tedge-container-bundle:$VERSION
    ```

2. Create the image archive

    ```sh
    docker save --platform "$PLATFORM" ghcr.io/thin-edge/tedge-container-bundle:$VERSION \
    | gzip > tedge-container-bundle.tar.gz
    ```

3. Add a new version with the archive attached

    ```sh
    c8y software versions create \
        --software tedge \
        --version "ghcr.io/thin-edge/tedge-container-bundle:$VERSION" \
        --file ./tedge-container-bundle.tar.gz
    ```

4. Install it

    ```sh
    c8y software versions install \
        --device "subdevice01" \
        --action install \
        --software tedge \
        --version "ghcr.io/thin-edge/tedge-container-bundle:$VERSION"
    ```

The same can be triggered locally by adding a `url` to the `self_update` command:

```sh
tedge mqtt pub -r -q 2 'te/device/main///cmd/self_update/local-1' '{
    "status": "init",
    "image": "ghcr.io/thin-edge/tedge-container-bundle:$VERSION",
    "containerName": "tedge",
    "url": "http://192.168.1.10:8000/tedge-container-bundle.tar.gz"
}'
```

Though when triggering the operation locally ensure that you clean up the operation after it is has completed using:

```sh
tedge mqtt pub -r -q 2 'te/device/main///cmd/self_update/local-1' ''
```


### Self update from an image file on an older image

The workflow which installs the image from a url is part of the image itself, so a device
still running an image from before this feature ignores the url and falls back to pulling
from a container registry. Such a device can still be updated without registry access, by
loading the image into the container engine first and then triggering an ordinary self
update. Only the first update needs this, afterwards the url is handled by the device.

The container engine keeps the loaded image, and the self update only pulls an image when
the reference is not already present locally.

1. Upload the archive to Cumulocity as described above, then read the binary id from the end
   of the software version's url

    ```sh
    BINARY_ID=$(
        c8y software versions list \
            --software tedge \
            --version "ghcr.io/thin-edge/tedge-container-bundle:$VERSION" \
            --select c8y_Software.url \
            -o csv \
        | c8y template execute --template "local parts = std.split(input.value, '/'); parts[std.length(parts)-1]"
    )
    ```

2. Load the image into the device's container engine using a shell operation

    ```sh
    DEVICE_ID="device01"
    c8y operations create \
        --device "$DEVICE_ID" \
        --description "Load the tedge-container-bundle image" \
        --template "{c8y_Command:{text:'tedge http get /c8y/inventory/binaries/$BINARY_ID > /tmp/tedge-container-bundle.tar.gz && sudo -E tedge-container engine docker load --input /tmp/tedge-container-bundle.tar.gz && rm -f /tmp/tedge-container-bundle.tar.gz'}}"
    ```

    `tedge http get` sends the request via the local Cumulocity proxy, so no credentials are
    needed on the device. Make sure the device has enough free space for the archive.

3. Install the version without a binary, as the image is already on the device

    ```sh
    c8y software versions install \
        --device "$DEVICE_ID" \
        --action install \
        --software tedge \
        --softwareType container \
        --url " " \
        --version "ghcr.io/thin-edge/tedge-container-bundle:$VERSION"
    ```

The same two steps work for any future version, as they only use the shell operation and
the container engine, so they are a way out of any self update which cannot be performed by
the image currently on the device.


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
