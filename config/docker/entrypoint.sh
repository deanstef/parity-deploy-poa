#!/bin/bash
# Copyright 2019 Stefano De Angelis

help() {

echo "entrypoint.sh 
Usage:
REQUIRED:
        --config dev / aura / tendermint / validatorset / contract / input.json / custom_chain.toml

OPTIONAL:
        --name name_of_chain. Default: parity
        --nodes number_of_nodes (if using aura / tendermint) Default: 2
        --ethstats - Enable ethstats monitoring of authority nodes. Default: Off
        --expose - Expose a specific container on ports 8180 / 8545 / 30303. Default: Config specific
        --entrypoint - Use custom entrypoint for docker container e.g. /home/parity/bin/parity

NOTE:
    input.json - Custom spec files can be inserted by specifiying the path to the json file.
    custom_chain.toml - Custom toml file defining multiple nodes. See customchain/config/example.toml for an example.
"
}

ARGS="$@"

while [ "$1" != "" ]; do
        case $1 in
        -d | --delay)
                shift
                DELAY=$1
                ;;
        -j | --jitter)
                shift
                JITTER=$1
                ;;
        -c | --correlation)
                shift
                CORRELATION=$1
                ;;
        --distribution)
                shift
                DISTRIBUTION=$1
                ;;
        -h | --help)
                help
                exit
                ;;
        *) PARITY_OPTIONS="$PARITY_OPTIONS $1 " ;;
        esac
        shift
done
