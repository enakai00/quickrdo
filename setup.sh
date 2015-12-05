#!/bin/sh -e

export LANG=en_US.utf8

function prep {
    subscription-manager repos --disable=*
    subscription-manager repos \
        --enable=rhel-7-server-rpms \
        --enable=rhel-7-server-optional-rpms \
        --enable=rhel-7-server-extras-rpms \
        --enable=rhel-7-server-openstack-7.0-rpms

    yum -y install yum-plugin-priorities yum-utils
    for repo in rhel-7-server-openstack-7.0-rpms \
                rhel-7-server-rpms \
                rhel-7-server-optional-rpms \
                rhel-7-server-extras-rpms; do
        yum-config-manager --enable $repo --setopt="$repo.priority=1"
    done

    yum -y update
    yum -y install iptables-services
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service
}

function osp_install {
    extnic=$1
    privnic=$2
    yum -y install openstack-packstack
    ./lib/genanswer.sh controller $privnic
    packstack --answer-file=controller.txt
    openstack-config --set /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini ovs bridge_mappings "extnet:br-ex,privnet:br-priv"

    if ! ovs-vsctl list-ports br-ex | grep -q ${extnic}; then
        ovs-vsctl add-port br-ex ${extnic}
    fi

    if ! ovs-vsctl list-ports br-priv | grep -q ${privnic}; then
        ovs-vsctl add-port br-priv ${privnic}
    fi

    systemctl stop openstack-nova-compute.service 
    systemctl disable openstack-nova-compute.service 
fi
}

# main

extnic=""
while [[ -z $extnic ]]; do
    echo -n "External NIC: "
    read extnic
done

privnic=""
while [[ -z $privnic ]]; do
    echo -n "Private NIC: "
    read privnic
done


echo
echo "Doing preparations..."
echo
prep 2>/dev/null

echo
echo "Installing RHEL-OSP with packstack...."
echo
osp_install $extnic $privnic 2>/dev/null

echo
echo "Done. Now, you need to reboot the server."

