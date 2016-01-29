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

    packstack --gen-answer-file=answers.txt
    sed -i 's/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=n/' answers.txt
    sed -i 's/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' answers.txt
#    sed -i 's/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/' answers.txt
#    sed -i 's/CONFIG_HEAT_CLOUDWATCH_INSTALL=.*/CONFIG_HEAT_CLOUDWATCH_INSTALL=y/' answers.txt
#    sed -i 's/CONFIG_HEAT_CFN_INSTALL=.*/CONFIG_HEAT_CFN_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_CINDER_VOLUMES_CREATE=.*/CONFIG_CINDER_VOLUMES_CREATE=n/' answers.txt
    sed -i 's/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=.*/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=local/' answers.txt
    sed -i 's/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=.*/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=local/' answers.txt

    packstack --answer-file=answers.txt
}

# main

extnic=""
while [[ -z $extnic ]]; do
    echo -n "VM access NIC: "
    read extnic
done

echo
echo "Doing preparations..."
echo
prep 2>/dev/null

echo
echo "Installing RHEL-OSP with packstack...."
echo
osp_install 2>/dev/null

if ! ovs-vsctl list-ports br-ex | grep -q ${extnic}; then
    ovs-vsctl add-port br-ex ${extnic}
fi

echo
echo "Done. Now, you need to reboot the server."

