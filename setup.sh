#!/bin/sh -e

export LANG=en_US.utf8

function prep {
    yum -y update
    yum -y install iptables-services
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service
}

function rdo_install {
    extnic=$1
    subnets=$2
    yum -y install https://repos.fedorapeople.org/repos/openstack/openstack-liberty/rdo-release-liberty-2.noarch.rpm
    yum -y install openstack-packstack

#cp -f ~/packstack.rst /usr/share/packstack/
#cp -f ~/neutron_350.py /usr/lib/python2.7/site-packages/packstack/plugins/

    ./lib/genanswer.sh controller ${subnets}

    packstack --answer-file=controller.txt
    openstack-config --set /etc/neutron/plugins/ml2/openvswitch_agent.ini \
                     ovs bridge_mappings "extnet:br-ex"

    if ! ovs-vsctl list-ports br-ex | grep -q ${extnic}; then
        ovs-vsctl add-port br-ex ${extnic}
    fi

    systemctl stop openstack-nova-compute.service 
    systemctl disable openstack-nova-compute.service 
}

# main

extnic=""
while [[ -z $extnic ]]; do
    echo -n "External NIC: "
    read extnic
done

subnets=""
while [[ -z $subnets ]]; do
    echo -n "Tunneling subnets: "
    read subnets
done

echo
echo "Doing preparations..."
echo
prep 2>/dev/null

echo
echo "Installing RHEL-RDO with packstack...."
echo
rdo_install $extnic $subnets 2>/dev/null

echo
echo "Done. Now, you need to reboot the server."

