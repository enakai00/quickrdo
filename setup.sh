#!/bin/sh -e

export LANG=en_US.utf8

function prep {
    setenforce 0
    sed -i.bak 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

    yum update -y
    yum install -y iptables-services
    systemctl stop firewalld.service
    systemctl mask firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service
}

function rdo_install {
    yum -y install https://repos.fedorapeople.org/repos/openstack/openstack-liberty/rdo-release-liberty-2.noarch.rpm
    yum -y install openstack-packstack-7.0.0-0.7.dev1661.gaf13b7e.el7.noarch
    packstack --gen-answer-file=answers.txt
    sed -i 's/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=n/' answers.txt
    sed -i 's/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_HEAT_CLOUDWATCH_INSTALL=.*/CONFIG_HEAT_CLOUDWATCH_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_HEAT_CFN_INSTALL=.*/CONFIG_HEAT_CFN_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=.*/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=local/' answers.txt
    sed -i 's/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=.*/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=local/' answers.txt

    packstack --answer-file=answers.txt

    . ~/keystonerc_admin
    heat-manage db_sync

    # https://ask.openstack.org/en/question/87045/error-unable-to-retrieve-volume-limit-information/
    CINDER_PW=$(awk -F= '/CONFIG_CINDER_KS_PW/{print $2}' answers.txt)
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken auth_uri http://localhost:5000
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://localhost:35357
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken auth_plugin password
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken project_domain_id default
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken user_domain_id default
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken project_name services
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken username cinder
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken password $CINDER_PW
}

# main

echo
echo "Doing preparations..."
echo
prep 2>/dev/null

echo
echo "Installing RDO with packstack...."
echo
rdo_install 2>/dev/null

echo
echo "Done. Now, you need to reboot the server."

