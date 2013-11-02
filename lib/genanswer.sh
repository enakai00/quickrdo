#!/bin/sh

function controller {
    packstack --gen-answer-file=controller.txt
    cp controller.txt controller.txt.orig

    sed -i 's/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/' controller.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' controller.txt
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

    compute_ip=$(awk -F"=" '/CONFIG_NOVA_API_HOST=/{ print $2 }' compute.txt )
    sed -i "s/EXCLUDE_SERVERS=.*/EXCLUDE_SERVERS=${compute_ip}/" compute.txt
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
