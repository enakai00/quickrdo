#!/bin/sh

function controller {
    packstack --gen-answer-file=controller.txt
    cp controller.txt controller.txt.orig

    sed -i 's/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=n/' controller.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' controller.txt
    sed -i 's/CONFIG_CEILOMETER_INSTALL=.*/CONFIG_CEILOMETER_INSTALL=n/' controller.txt
    sed -i 's/CONFIG_NEUTRON_OVS_TENANT_NETWORK_TYPE=.*/CONFIG_NEUTRON_OVS_TENANT_NETWORK_TYPE=vlan/' controller.txt
    sed -i 's/CONFIG_NEUTRON_OVS_VLAN_RANGES=.*/CONFIG_NEUTRON_OVS_VLAN_RANGES=physnet1,physnet2:100:199/' controller.txt
    sed -i 's/CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=.*/CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=physnet1:br-ex,physnet2:br-priv/' controller.txt
    sed -i 's/CONFIG_SWIFT_STORAGE_SIZE=.*/CONFIG_SWIFT_STORAGE_SIZE=20G/' controller.txt
}

function compute {
    node=$1
    if [[ ! -f controller.txt ]]; then
        echo "You need controller.txt."
        exit 1
    fi
    cp -f controller.txt compute.txt

    compute_ip=$(awk -F"=" '/CONFIG_NOVA_API_HOST=/{ print $2 }' compute.txt)
    sed -i "s/EXCLUDE_SERVERS=.*/EXCLUDE_SERVERS=${compute_ip}/" compute.txt
    sed -i "s/CONFIG_NOVA_COMPUTE_HOSTS=.*/CONFIG_NOVA_COMPUTE_HOSTS=${node}/" compute.txt
    sed -i "s/CONFIG_CINDER_HOST=.*/CONFIG_CINDER_HOST=${node}/" compute.txt
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
