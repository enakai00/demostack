#!/bin/sh

function controller {
    packstack --gen-answer-file=controller.txt
    cp controller.txt controller.txt.orig

    sed -i 's/CONFIG_CINDER_VOLUMES_CREATE=.*/CONFIG_CINDER_VOLUMES_CREATE=n/' controller.txt
    sed -i 's/CONFIG_QUANTUM_OVS_TENANT_NETWORK_TYPE=.*/CONFIG_QUANTUM_OVS_TENANT_NETWORK_TYPE=vlan/' controller.txt
    sed -i 's/CONFIG_QUANTUM_OVS_VLAN_RANGES=.*/CONFIG_QUANTUM_OVS_VLAN_RANGES=physnet2:100:199/' controller.txt
    sed -i 's/CONFIG_QUANTUM_OVS_BRIDGE_MAPPINGS=.*/CONFIG_QUANTUM_OVS_BRIDGE_MAPPINGS=physnet2:br-priv/' controller.txt
}

function compute {
    node=$1
    if [[ ! -f controller.txt ]]; then
        echo "You need controller.txt."
        exit 1
    fi
    cp -f controller.txt compute.txt

    sed -i 's/CONFIG_CINDER_INSTALL=.*/CONFIG_CINDER_INSTALL=n/' compute.txt
    sed -i 's/CONFIG_HORIZON_INSTALL=.*/CONFIG_HORIZON_INSTALL=n/' compute.txt
    sed -i 's/CONFIG_CLIENT_INSTALL=.*/CONFIG_CLIENT_INSTALL=n/' compute.txt
    sed -i "s/CONFIG_NOVA_COMPUTE_HOSTS=.*/CONFIG_NOVA_COMPUTE_HOSTS=${node}/" compute.txt
}

function main {
    case $1 in

      "controller")
        controller
	;;

      "compute")
        compute $2
        ;;

      *)
        echo "Usage: $0 controller|compute <IP>"
    esac
}

main $@

