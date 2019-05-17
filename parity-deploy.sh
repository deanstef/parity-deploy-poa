#!/bin/bash
# Copyright 2017 Parity Technologies (UK) Ltd.
# Copyright edit by Stefano De Angelis.

# TODO:
# 1. BUGFIX: Add client node. Configure properly docker compose. Actually generates error due to a bad formating of docker-compose. Indeed client service must added before the volumes.

CHAIN_NAME="parity"
CHAIN_NODES="1"
CLIENT="0"
DOCKER_INCLUDE="include/docker-compose.yml"
help() {

	echo "parity-deploy.sh OPTIONS
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

check_packages() {

	if [ $(grep -i debian /etc/*-release | wc -l) -gt 0 ]; then
		if [ ! -f /usr/bin/docker ]; then
			sudo apt-get -y install docker.io python-pip
		fi

		if [ ! -f /usr/local/bin/docker-compose ]; then
			sudo pip install docker-compose
		fi
	fi
}

genpw() {

	openssl rand -base64 12

}

# Generate for each node its keys, password and address, using both ethstore and ethkey.

create_node_params() {

	local DEST_DIR=deployment/$1
	if [ ! -d $DEST_DIR ]; then
		mkdir -p $DEST_DIR
	fi

	# Generate random password
	if [ ! -f $DEST_DIR/password ]; then
		openssl rand -base64 12 >$DEST_DIR/password
	fi
	./config/utils/keygen.sh $DEST_DIR

	PASSWORD=$(cat $DEST_DIR/password)
	PRIV_KEY=$(cat $DEST_DIR/key.priv)
	./ethstore insert ${PRIV_KEY} $DEST_DIR/password --dir $DEST_DIR/parity >$DEST_DIR/address.txt

        # echo [val1] > [val2] substitute the content of [val2] with [val1]
	echo "NETWORK_NAME=$CHAIN_NAME" >.env
}

# For each node we capture the enodes in reserved_peers

create_reserved_peers_poa() {

	PUB_KEY=$(cat deployment/$1/key.pub)
	echo "enode://$PUB_KEY@host$1:30303" >>deployment/chain/reserved_peers
}

create_reserved_peers_instantseal() {

	PUB_KEY=$(cat deployment/$1/key.pub)
	echo "enode://$PUB_KEY@127.0.0.1:30303" >>deployment/chain/reserved_peers

}

build_spec() {

	display_header
	display_name
	display_engine
	display_params
	display_genesis
	display_accounts
	display_footer

}

# Build the docker-compose.yml file for poa network

build_docker_config_poa() {

	echo "version: '2.0'" >docker-compose.yml
	echo "services:" >>docker-compose.yml

	for x in $(seq 1 $CHAIN_NODES); do
		cat config/docker/authority.yml | sed -e "s/NODE_NAME/$x/g" | sed -e "s@-d /home/parity/data@-d /home/parity/data $PARITY_OPTIONS@g" >>docker-compose.yml
		mkdir -p data/$x
	done

	# BUGFIX. Here should look for client service. If present call build_docker_client()

	build_docker_config_ethstats

        # add user privileges for containers within custom volumes
	cat $DOCKER_INCLUDE >>docker-compose.yml

	chown -R $USER data/
}

build_docker_config_ethstats() {

	if [ "$ETHSTATS" == "1" ]; then
		cat include/ethstats.yml >>docker-compose.yml
	fi
}

build_docker_config_instantseal() {

	cat config/docker/instantseal.yml | sed -e "s@-d /home/parity/data@-d /home/parity/data $PARITY_OPTIONS@g" >docker-compose.yml

	build_docker_config_ethstats

        cat $DOCKER_INCLUDE >>docker-compose.yml

        mkdir -p data/is_authority

        chown -R $USER data/
}

# Generates one container for a client node. TODO: 1. Multiple clients, 2. Add client account
build_docker_client() {

	if [ "$CLIENT" == "1" ]; then
		create_node_params client
		cp config/spec/client.toml deployment/client/
		cat config/docker/client.yml >>docker-compose.yml

		# writing client dependencies with respect the other services
		if [ "$CHAIN_NODES" -gt "0" ]; then
			echo "       depends_on:" >>docker-compose.yml

			for x in $(seq 1 $CHAIN_NODES); do
				echo "       - \"host${x}\"" >>docker-compose.yml
			done
		fi
	fi
}

build_custom_chain() {

	if [ -z "$CUSTOM_CHAIN" ]; then
		echo "Must specify argument for custom chain option."
		exit 1
	fi

	./customchain/generate.py "$CUSTOM_CHAIN"

	exit 0
}

display_header() {

	cat config/spec/chain_header

}

display_footer() {

	cat config/spec/chain_footer
}

display_name() {

	cat config/spec/name | sed -e "s/CHAIN_NAME/$CHAIN_NAME/g"
}

# Generate the .toml config file for a poa node.

create_node_config_poa() {

	ENGINE_SIGNER=$(cat deployment/$1/address.txt)
	if [ "$CHAIN_ENGINE" == "contract" ]; then
		cat config/spec/authority_unlock.toml | sed -e "s/ENGINE_SIGNER/$ENGINE_SIGNER/g; s/ACCOUNT_ADDR/$ENGINE_SIGNER/g" >deployment/$1/authority.toml
	else
		cat config/spec/authority_round.toml | sed -e "s/ENGINE_SIGNER/$ENGINE_SIGNER/g" >deployment/$1/authority.toml
	fi
}

create_node_config_instantseal() {

	ENGINE_SIGNER=$(cat deployment/$1/address.txt)
	cat config/spec/instant_seal.toml | sed -e "s/ENGINE_SIGNER/$ENGINE_SIGNER/g" >deployment/$1/authority.toml

}

# if multiple elements in input, port mapping needed
expose_container() {

	if [ -z "$1" ]; then
		PORT_1=8080
		PORT_2=8180
		PORT_RPC=8545
		PORT_WS=8546
		PORT_NET=30303

		for x in $(seq 1 $CHAIN_NODES); do
			sed -i "s@container_name: host$x@&\n       ports:\n       - $PORT_1:8080\n       - $PORT_2:8180\n       - $PORT_RPC:8545\n       - $PORT_WS:8546\n       - $PORT_NET:30303@g" docker-compose.yml
			((PORT_1++))
			((PORT_2++))
			((PORT_RPC+=2))
			((PORT_WS+=2))
			((PORT_NET++))
		done
	else
		sed -i "s@container_name: $1@&\n       ports:\n       - 8080:8080\n       - 8180:8180\n       - 8545:8545\n       - 8546:8546\n       - 30303:30303@g" docker-compose.yml
	fi
}

# Se --expose vengono mappate le porte sugli host richiesti, altrimenti viene esposto host1 o il nodo client se presente.

# NB could be an array of clients e.g. host1, host2, host3
select_exposed_container() {

	#if [ -n "$EXPOSE_CLIENT" ]; then
	#	expose_container $EXPOSE_CLIENT
	if [ "$EXPOSE_CLIENT" = "all" ]; then
		expose_container
	else
		if [ "$CLIENT" == "0" ]; then
			expose_container host1
		fi
	fi

}

display_engine() {

	case $CHAIN_ENGINE in
	dev)
		cat config/spec/engine/instantseal
		;;
	aura | validatorset | tendermint | contract)
		for x in $(seq 1 $CHAIN_NODES); do
			VALIDATOR=$(cat deployment/$x/address.txt)
			RESERVED_PEERS="$RESERVED_PEERS $VALIDATOR"
			VALIDATORS="$VALIDATORS \"$VALIDATOR\","
		done
		# Remove trailing , from validator list
		VALIDATORS=$(echo $VALIDATORS | sed 's/\(.*\),.*/\1/')
		cat config/spec/engine/$CHAIN_ENGINE | sed -e "s/0x0000000000000000000000000000000000000000/$VALIDATORS/g"
		;;
	*)
		echo "Unknown engine: $CHAIN_ENGINE"
		;;
	esac

}

display_params() {

	if [ "$CHAIN_ENGINE" == "contract" ]; then
		CHAIN_ENGINE=aura
	fi

	cat config/spec/params/$CHAIN_ENGINE
}

display_genesis() {

	cat config/spec/genesis/$CHAIN_ENGINE

}

display_accounts() {

				ACC_TMP=$(mktemp)
				cat config/spec/accounts/$CHAIN_ENGINE > $ACC_TMP
        for x in $(seq $CHAIN_NODES); do
                ACCOUNT_ADDR=$(cat deployment/$x/address.txt)
                sed -i "s@\"accounts\": {@&\n        \"$ACCOUNT_ADDR\": { \"balance\": \"1606938044258990275541962092341162602522202993782792835301376\" },@g" $ACC_TMP
        done

        cat $ACC_TMP
				rm $ACC_TMP
}

ARGS="$@"

while [ "$1" != "" ]; do
	case $1 in
	--name)
		shift
		CHAIN_NAME=$1
		;;
	-c | --config)
		shift
		CHAIN_ENGINE=$1
		;;
	-n | --nodes)
		shift
		CHAIN_NODES=$1
		;;
	-r | --release)
		shift
		PARITY_RELEASE=$1
		;;
	-e | --ethstats)
		ETHSTATS=1
		;;
	--enable-client)
		CLIENT=1
		;;
	--expose)
		shift
		EXPOSE_CLIENT="$1"
		;;
	--chain)
		shift
		CHAIN_NETWORK=$1
		;;
	--entrypoint)
		shift
		ENTRYPOINT=$1
		;;
	--netem)
		shift
		NETEM_PARAMS="$1"
		;;
	-h | --help)
		help
		exit
		;;
	*) PARITY_OPTIONS="$PARITY_OPTIONS $1 " ;;
	esac
	shift
done

#Controllo che engine e network non siano nulle

if [ -z "$CHAIN_ENGINE" ] && [ -z "$CHAIN_NETWORK" ]; then
	echo "No chain argument, exiting..."
	exit 1
fi

mkdir -p deployment/chain
check_packages

# if custom toml file with multiple nodes is provided, run the customchain script.
# this script generates the docker-compose, the config files for containers and the chain spec.json, specified within the custom toml.
echo $CHAIN_ENGINE | grep -q toml
if [ $? -eq 0 ]; then
	./customchain/generate.py "$CHAIN_ENGINE"
	exit 0
fi

###
###				docker-compose implementation

# If chain network param is present( --chain), load in each container config the name of the network and, if also parity parameters are present, they are also loaded within the command key.
# --> configuration to run a single client node of a predefined chain.
if [ ! -z "$CHAIN_NETWORK" ]; then
	if [ ! -z "$PARITY_OPTIONS" ]; then
		cat config/docker/chain.yml | sed -e "s/CHAIN_NAME/$CHAIN_NETWORK/g" | sed -e "s@-d /home/parity/data@-d /home/parity/data $PARITY_OPTIONS@g" >docker-compose.yml

	else
		cat config/docker/chain.yml | sed -e "s/CHAIN_NAME/$CHAIN_NETWORK/g" >docker-compose.yml
	fi

# Else the custom chain network has not been specified. Currently the script supports two chains: dev/aura.

# --config dev
elif [ "$CHAIN_ENGINE" == "dev" ]; then
	echo "using instantseal"
	create_node_params is_authority
	create_reserved_peers_instantseal is_authority
	create_node_config_instantseal is_authority
	build_docker_config_instantseal

# --config aura|validatorset|tendermint
elif [ "$CHAIN_ENGINE" == "aura" ] || [ "$CHAIN_ENGINE" == "validatorset" ] || [ "$CHAIN_ENGINE" == "tendermint" ] || [ "$CHAIN_ENGINE" == "contract" ] || [ -f "$CHAIN_ENGINE" ]; then
	if [ $CHAIN_NODES ]; then
		# per ogni nodo genera i file di configurazione
		for x in $(seq $CHAIN_NODES); do
			create_node_params $x
			create_reserved_peers_poa $x
			create_node_config_poa $x
		done
		build_docker_config_poa
		build_docker_client # BUG. docker-compose bad formatted. the client service must be added before the volumes.
	fi

        # Create the chain spec file .json
	if [ "$CHAIN_ENGINE" == "aura" ] || [ "$CHAIN_ENGINE" == "validatorset" ] || [ "$CHAIN_ENGINE" == "tendermint" ] || [ "$CHAIN_ENGINE" == "contract" ]; then
		build_spec >deployment/chain/spec.json
	else
		mkdir -p deployment/chain
		cp $CHAIN_ENGINE deployment/chain/spec.json
	fi

else

	echo "Could not find spec file: $CHAIN_ENGINE"
fi

if [ ! -z $PARITY_RELEASE ]; then
    echo "Custom release ${PARITY_RELEASE} selected. WARNING: This may not be compatible with all parity docker images"
	DOCKER_TMP=$(mktemp)
	cat docker-compose.yml | sed -e "s@image: parity/parity:stable@image: parity/parity:${PARITY_RELEASE}@g" > $DOCKER_TMP
	mv $DOCKER_TMP docker-compose.yml
fi

if [ ! -z $ENTRYPOINT ]; then
    ENTRYPOINT_TMP=$(mktemp)
    cat docker-compose.yml | sed -e "s@user: parity@user: parity\n       entrypoint: ${ENTRYPOINT}@g" > $ENTRYPOINT_TMP
    	if [ ! -z "$NETEM_PARAMS" ]; then
		#echo $NETEM_PARAMS
		#echo $(wc -w <<< "$NETEM_PARAMS")
		COUNT=0
		for param in $NETEM_PARAMS; do
			((COUNT+=1))
			case $COUNT in
				1)
					NETEM_DELAY=$param
					;;
				2)
					NETEM_JITTER=$param
					;;
				3)	NETEM_CORRELATION=$param
					;;
				4)	NETEM_DISTRIBUTION=$param
					;;
			esac
		done

		if [ ! -z $NETEM_DELAY ]; then
			echo "DELAY="$NETEM_DELAY
		fi
                if [ ! -z $NETEM_JITTER ]; then
                        echo "JITTER="$NETEM_JITTER
                fi
                if [ ! -z $NETEM_CORRELATION ]; then
                        echo "CORRELATION="$NETEM_CORRELATION
                fi
                if [ ! -z $NETEM_DISTRIBUTION ]; then
                        echo "DISTRIBUTION="$NETEM_DISTRIBUTION
                fi
	fi
    mv $ENTRYPOINT_TMP docker-compose.yml
fi

select_exposed_container
