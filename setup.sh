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
    yum -y install openstack-packstack
    ./lib/genanswer.sh controller
    packstack --answer-file=controller.txt

    systemctl stop openstack-nova-compute.service 
    systemctl disable openstack-nova-compute.service 
}

# main

echo
echo "Doing preparations..."
echo
prep 2>/dev/null

echo
echo "Installing RDO with packstack...."
echo
osp_install 2>/dev/null

echo
echo "Done. Now, you need to reboot the server."

