#!/bin/sh

function controller {
    privnic=$1
    packstack --gen-answer-file=controller.txt
    cp controller.txt controller.txt.orig

    sed -i 's/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=n/' controller.txt
    sed -i 's/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/' controller.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' controller.txt
    sed -i 's/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/' controller.txt
    sed -i 's/CONFIG_HEAT_CLOUDWATCH_INSTALL=.*/CONFIG_HEAT_CLOUDWATCH_INSTALL=y/' controller.txt
    sed -i 's/CONFIG_HEAT_CFN_INSTALL=.*/CONFIG_HEAT_CFN_INSTALL=y/' controller.txt
    sed -i 's/CONFIG_CINDER_VOLUMES_CREATE=.*/CONFIG_CINDER_VOLUMES_CREATE=n/' controller.txt
    sed -i 's/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=.*/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=vxlan,flat/' controller.txt
    sed -i "s/CONFIG_NEUTRON_OVS_TUNNEL_IF=.*/CONFIG_NEUTRON_OVS_TUNNEL_IF=$privnic/" controller.txt
}

function compute {
    node=$1
    if [[ ! -f controller.txt ]]; then
        echo "You need controller.txt."
        exit 1
    fi
    if [[ ! -f compute.txt ]]; then
        cp -f controller.txt compute.txt
        sed -i "s/CONFIG_COMPUTE_HOSTS=.*/CONFIG_COMPUTE_HOSTS=${node}/" compute.txt
    else
        compute_nodes=$(awk -F"=" '/CONFIG_COMPUTE_HOSTS=/{ print $2 }' compute.txt )
        if ! echo $compute_nodes | grep -q $node; then
            compute_nodes="${compute_nodes},${node}"
        fi
        sed -i "s/CONFIG_COMPUTE_HOSTS=.*/CONFIG_COMPUTE_HOSTS=${compute_nodes}/" compute.txt
    fi
}

function main {
    case $1 in

      "controller")
        controller $2
        ;;

      "compute")
        compute $2 $3
        ;;

      *)
        echo "Usage: $0 controller|compute <IP>"
    esac
}

main $@
