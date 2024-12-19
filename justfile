set dotenv-load
set export

IMAGE := "tedge-container-bundle"
TEDGE_IMAGE := "tedge"
TEDGE_TAG := "1.4.1"

REGISTRY := "ghcr.io"
REPO_OWNER := "thin-edge"
DEFAULT_OUTPUT_TYPE := "registry,dest=" + IMAGE + ".tar"

RELEASE_VERSION := env_var_or_default("RELEASE_VERSION", `date +'%Y%m%d.%H%M'`)

# Test Variables
TEST_IMAGE := env_var_or_default("TEST_IMAGE", "docker:27-dind")


# Initialize a dotenv file for usage with a local debugger
# WARNING: It will override any previously generated dotenv file
init-dotenv:
  @echo "Recreating .env file..."
  @echo "TEST_IMAGE=$IMAGE" >> .env
  @echo "C8Y_BASEURL=$C8Y_BASEURL" >> .env
  @echo "C8Y_USER=$C8Y_USER" >> .env
  @echo "C8Y_PASSWORD=$C8Y_PASSWORD" >> .env


# Enabling running cross platform tools when building container images
build-setup:
    docker buildx install
    docker run --privileged --rm tonistiigi/binfmt --install all

# Build docker images (for testing)
build OUTPUT_TYPE=DEFAULT_OUTPUT_TYPE VERSION='latest': build-setup
    docker buildx build \
        --label "org.opencontainers.image.version={{VERSION}}" \
        --build-arg "TEDGE_IMAGE={{TEDGE_IMAGE}}" \
        --build-arg "TEDGE_TAG={{TEDGE_TAG}}" \
        -t "{{REGISTRY}}/{{REPO_OWNER}}/{{IMAGE}}:{{VERSION}}" \
        -t "{{REGISTRY}}/{{REPO_OWNER}}/{{IMAGE}}:latest" \
        -f Dockerfile \
        --output=type="{{OUTPUT_TYPE}}",oci-mediatypes=false \
        --provenance=false \
        .

# Publish docker images (multi-arch)
# Example:
#    just publish registry latest
#    just publish registry 1.2.0
# Use oci-mediatypes=false to improve compatibility with older docker versions, e.g. <= 19.0.x
# See https://github.com/docker/buildx/issues/1964#issuecomment-1644634461
publish OUTPUT_TYPE=DEFAULT_OUTPUT_TYPE VERSION='latest': build-setup
    docker buildx build \
        --platform linux/arm/v6,linux/arm/v7,linux/amd64,linux/arm64 \
        --label "org.opencontainers.image.version={{VERSION}}" \
        --build-arg "TEDGE_IMAGE={{TEDGE_IMAGE}}" \
        --build-arg "TEDGE_TAG={{TEDGE_TAG}}" \
        -t "{{REGISTRY}}/{{REPO_OWNER}}/{{IMAGE}}:{{VERSION}}" \
        -t "{{REGISTRY}}/{{REPO_OWNER}}/{{IMAGE}}:latest" \
        -f Dockerfile \
        --output=type="{{OUTPUT_TYPE}}",oci-mediatypes=false \
        --provenance=false \
        .

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

# --------------------------------------------
# System Tests
# --------------------------------------------

# Build test images
build-test: build-test-bundles
    echo "Creating test infrastructure image"
    [ -d "./test-images/{{TEST_IMAGE}}" ] && docker build --load -t {{TEST_IMAGE}} -f ./test-images/{{TEST_IMAGE}}/Dockerfile . || docker pull "{{TEST_IMAGE}}"

build-test-bundles:
    echo "Building tedge-container-bundle images"
    just build "docker,dest=./tests/tedge-container-bundle_99.99.1.tar.gz" 99.99.1
    just build "docker,dest=./tests/tedge-container-bundle_99.99.2.tar.gz" 99.99.2

# Run tests
test *ARGS='':
    ./.venv/bin/python3 -m robot.run --listener RetryFailed --outputdir output {{ARGS}} tests

# Run self-update tests
test-self-update *ARGS='':
    ./.venv/bin/python3 -m robot.run --include "self-update" --outputdir output {{ARGS}} tests

# Trigger a release (by creating a tag)
release:
    git tag -a "{{RELEASE_VERSION}}" -m "{{RELEASE_VERSION}}"
    git push origin "{{RELEASE_VERSION}}"
    @echo
    @echo "Created release (tag): {{RELEASE_VERSION}}"
    @echo

#
# Local start/stop container helpers
# This is only meant for quick local experiments on the host's container engine
#
# Start local instance
local-start *ARGS:
    BUILD_DIR=./tests ./test-images/common/container-bundle.sh start {{ARGS}}

# Stop local instance
local-stop *ARGS:
    BUILD_DIR=./tests ./test-images/common/container-bundle.sh stop {{ARGS}}

local-delete *ARGS:
    BUILD_DIR=./tests ./test-images/common/container-bundle.sh delete {{ARGS}}
