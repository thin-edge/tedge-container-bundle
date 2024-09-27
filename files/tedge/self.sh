#!/bin/sh
set -e

EXIT_OK=0
EXIT_USAGE=1
EXIT_FAILURE=2
# EXIT_RETRY=3

usage() {
    cat << EOF
USAGE
    self update software management plugin for thin-edge.io
    This sm-plugin is a bit special as it does not technically perform the update
    however it provides a way to get the current information about the deployed container
    and a clean way that the UI can trigger the update which is actually carried out
    by the self_update workflow

    $0 <COMMAND> [MODULE_NAME] [--module-version [VERSION]] [--file [FILE]]

    $0 list
    $0 prepare
    $0 install <MODULE_NAME> [--module-version [VERSION]] [--file [FILE]]
    $0 remove <MODULE_NAME> [--module-version [VERSION]]
    $0 finalize
EOF
}

MODULE_NAME=
MODULE_VERSION=
FILE=

log() { echo "$@" >&2; }

if [ $# -lt 1 ]; then
    log "Invalid number of positional arguments"
    usage
    exit "$EXIT_USAGE"
fi

# argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --module-version)
        MODULE_VERSION="$2"
        shift
        ;;
    --file)
        FILE="$2"
        shift
        ;;
    -h|--help)
        usage
        exit "$EXIT_USAGE"
        ;;
    --*|-*)
        log "Unknown option $1"
        exit "$EXIT_USAGE"
        ;;
    *)
        if [ -z "$COMMAND" ]; then
            COMMAND="$1"
        elif [ -z "$MODULE_NAME" ]; then
            MODULE_NAME="$1"
        fi
      ;;
  esac
  shift
done

case "$COMMAND" in
    prepare)
        ;;
    list)
        self_update.sh version
        ;;
    install)
        if [ -n "$FILE" ]; then
            log "Installing from file: $FILE"
        else
            MODULE="$MODULE_NAME"
            if [ -n "$MODULE_VERSION" ] && [ "$MODULE_VERSION" != "latest" ]; then
                MODULE="${MODULE_NAME}=${MODULE_VERSION}"
            fi

            log "Installing: $MODULE"
        fi
        ;;
    remove)
        echo "not supported"
        exit "$EXIT_FAILURE"
        ;;
    update-list)
        # Not supported, use remove install and remove instead
        exit "$EXIT_USAGE"
        ;;
    finalize)
        ;;
    *)
        log "Unsupported command: $COMMAND"
        exit 1
        ;;
esac

exit "$EXIT_OK"
