
IMAGE := "tedge-container-bundle"
TAG := "latest"
ENV_FILE := ".env"

# Build the docker image
build *ARGS:
    docker build -t "{{IMAGE}}:{{TAG}}" {{ARGS}} .

run-container *ARGS: build
    docker run -it --rm --tmpfs /tmp --env-file "{{ENV_FILE}}" {{ARGS}} "{{IMAGE}}:{{TAG}}"

# Start the compose project
start *ARGS:
    docker compose up --build {{ARGS}}

# Stop the compose project
stop *ARGS:
    docker compose down {{ARGS}}
