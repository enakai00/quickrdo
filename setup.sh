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
    # https://bugzilla.redhat.com/show_bug.cgi?id=1014311
    yum -y install mariadb-server
    rm -f /usr/lib/systemd/system/mariadb.service
    cp /usr/lib/systemd/system/mysqld.service /usr/lib/systemd/system/mariadb.service

    yum -y install http://repos.fedorapeople.org/repos/openstack/openstack-havana/rdo-release-havana-8.noarch.rpm
    yum -y install openstack-packstack-2013.2.1-0.36.dev1013.fc20.noarch
    packstack --gen-answer-file=answers.txt
    sed -i 's/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=n/' answers.txt
    sed -i 's/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_HEAT_CLOUDWATCH_INSTALL=.*/CONFIG_HEAT_CLOUDWATCH_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_HEAT_CFN_INSTALL=.*/CONFIG_HEAT_CFN_INSTALL=y/' answers.txt
    packstack --answer-file=answers.txt

    . ~/keystonerc_admin
    heat-manage db_sync
    # https://bugzilla.redhat.com/show_bug.cgi?id=1106394
    openstack-config --set --existing /etc/heat/heat.conf ec2authtoken auth_uri http://127.0.0.1:5000/v2.0

    heat_filter='-A INPUT -p tcp -m multiport --dports 8000,8003 -m comment --comment "001 heat API" -j ACCEPT'
    if ! grep -q -- "$heat_filter" /etc/sysconfig/iptables; then
         sed -i "/^:nova-filter-top - .*/a $heat_filter" /etc/sysconfig/iptables
    fi

    if virsh net-info default | grep -q -E "Active: *yes"; then
        virsh net-destroy default
        virsh net-autostart default --disable
    fi
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

