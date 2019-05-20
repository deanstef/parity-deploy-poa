#!/bin/bash
# Copyright 2019 Stefano De Angelis
DELAY=100
JITTER=5
CORRELATION=10
DISTRIBUTION=normal

help() {

echo "entrypoint.sh

Usage:

REQUIRED:
        -d <netem_delay> (default 100ms)
        -j <netem_jitter> (default 5ms)
        -c <netem_correlation> (default 10%)
        -t <netem_distribution> (default normal)

NOTE:
    Custom script fot tc (TrafficControl) command configuration. In this work we use tc to setup network delays.
    netem emulator is used to inject network delays in each docker container, it requires the following parameters:
    - Network delay
    - Delay jitter
    - Correlation
    - Distribution {uniform | normal | pareto |  paretonormal}
"
}

while getopts d:j:c:d:h option
do
  case "${option}" in
    d) DELAY=${OPTARG};;
    j) JITTER=${OPTARG};;
    c) CORRELATION=${OPTARG};;
    t) DISTRIBUTION=$OPTARG;;
    h) help
       exit
       ;;
  esac
done

#echo "$DELAY"ms
#echo "$JITTER"ms
#echo "$CORRELATION"%
#echo $DISTRIBUTION
tc qdisc add dev eth0 root netem delay "$DELAY"ms "$JITTER"ms "$CORRELATION"% distribution $DISTRIBUTION
/bin/parity --chain /home/parity/spec.json --config /home/parity/authority.toml -d /home/parity/data
