set dotenv-load

IMAGE := "tedge-container-bundle"
TEDGE_IMAGE := "tedge"
TEDGE_TAG := "1.3.0"
TAG := "latest"
ENV_FILE := ".env"

REGISTRY := "ghcr.io"
REPO_OWNER := "thin-edge"
DEFAULT_OUTPUT_TYPE := "registry,dest=" + IMAGE + ".tar"

RELEASE_VERSION := env_var_or_default("RELEASE_VERSION", `date +'%Y%m%d.%H%M'`)

# Initialize the device certificate and upload to Cumulocity
init *ARGS:
    docker compose --profile init up --build {{ARGS}}

# Start the compose project
start *ARGS: build-local
    COMPOSE_PROJECT_NAME= docker compose --profile service up --build {{ARGS}}

# Stop the compose project
stop *ARGS:
    docker compose down {{ARGS}}

# Enabling running cross platform tools when building container images
build-setup:
    docker run --privileged --rm tonistiigi/binfmt --install all

# Build a local image that can be used for self update
build-local:
    COMPOSE_PROJECT_NAME= docker compose --profile service build
    docker tag tedge-container-bundle-tedge tedge-container-bundle-tedge-next

# Run the image localy using docker only (not docker compose)
run-local: build-local
    docker rm -f tedge
    docker run -d \
        --name tedge \
        --restart=always \
        --network tedge \
        --tmpfs /tmp \
        -v "device-certs:/etc/tedge/device-certs" \
        -v "tedge:/data/tedge" \
        -v /var/run/docker.sock:/var/run/docker.sock:rw \
        -e "TEDGE_C8Y_URL=$TEDGE_C8Y_URL" \
        tedge-container-bundle-tedge

# Build the docker images
# Example:
#    just build registry latest
#    just build registry 1.2.0
# Use oci-mediatypes=false to improve compatibility with older docker verions, e.g. <= 19.0.x
# See https://github.com/docker/buildx/issues/1964#issuecomment-1644634461
build OUTPUT_TYPE=DEFAULT_OUTPUT_TYPE VERSION='latest': build-setup
    docker buildx build --platform linux/arm/v6,linux/arm/v7,linux/amd64,linux/arm64 --build-arg "TEDGE_IMAGE={{TEDGE_IMAGE}}" --build-arg "TEDGE_TAG={{TEDGE_TAG}}" -t "{{REGISTRY}}/{{REPO_OWNER}}/{{IMAGE}}:{{VERSION}}" -t "{{REGISTRY}}/{{REPO_OWNER}}/{{IMAGE}}:latest" -f Dockerfile --output=type="{{OUTPUT_TYPE}}",oci-mediatypes=false --provenance=false .

# Install python virtual environment
venv:
    [ -d .venv ] || python3 -m venv .venv
    ./.venv/bin/pip3 install -r tests/requirements.txt

# Format tests
format *ARGS:
    ./.venv/bin/python3 -m robotidy tests {{ARGS}}

# Run linter on tests
lint *ARGS:
    ./.venv/bin/python3 -m robocop --report rules_by_error_type --threshold W tests {{ARGS}}

# Run tests
test *ARGS='':
    ./.venv/bin/python3 -m robot.run --outputdir output {{ARGS}} tests

# Run self-update tests
test-self-update *ARGS='':
    just -f {{justfile()}} run-local
    ./.venv/bin/python3 -m robot.run --include "self-update" --outputdir output {{ARGS}} tests

# Cleanup device and all it's dependencies
cleanup DEVICE_ID $CI="true":
    echo "Removing device and child devices (including certificates)"
    c8y devicemanagement certificates list -n --tenant "$(c8y currenttenant get --select name --output csv)" --filter "name eq {{DEVICE_ID}}" --pageSize 2000 | c8y devicemanagement certificates delete --tenant "$(c8y currenttenant get --select name --output csv)"
    c8y inventory find -n --owner "device_{{DEVICE_ID}}" -p 100 | c8y inventory delete
    c8y users delete -n --id "device_{{DEVICE_ID}}" --tenant "$(c8y currenttenant get --select name --output csv)" --silentStatusCodes 404 --silentExit

# Trigger a release (by creating a tag)
release:
    git tag -a "{{RELEASE_VERSION}}" -m "{{RELEASE_VERSION}}"
    git push origin "{{RELEASE_VERSION}}"
    @echo
    @echo "Created release (tag): {{RELEASE_VERSION}}"
    @echo
