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

    yum -y install http://repos.fedorapeople.org/repos/openstack/openstack-havana/rdo-release-havana-9.noarch.rpm
    yum -y install openstack-packstack-2013.2.1-0.37.dev1048.fc20.noarch
    packstack --gen-answer-file=answers.txt
    sed -i 's/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=n/' answers.txt
    sed -i 's/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_NAGIOS_INSTALL=.*/CONFIG_NAGIOS_INSTALL=n/' answers.txt
    sed -i 's/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_HEAT_CLOUDWATCH_INSTALL=.*/CONFIG_HEAT_CLOUDWATCH_INSTALL=y/' answers.txt
    sed -i 's/CONFIG_HEAT_CFN_INSTALL=.*/CONFIG_HEAT_CFN_INSTALL=y/' answers.txt
    packstack --answer-file=answers.txt

    # https://bugzilla.redhat.com/show_bug.cgi?id=1103800
    list=( "/usr/lib/python2.7/site-packages/ceilometer/openstack/common/rpc/impl_qpid.py" \
           "/usr/lib/python2.7/site-packages/cinder/openstack/common/rpc/impl_qpid.py" \
           "/usr/lib/python2.7/site-packages/heat/openstack/common/rpc/impl_qpid.py" \
           "/usr/lib/python2.7/site-packages/keystone/openstack/common/rpc/impl_qpid.py" \
           "/usr/lib/python2.7/site-packages/neutron/openstack/common/rpc/impl_qpid.py" \
           "/usr/lib/python2.7/site-packages/nova/openstack/common/rpc/impl_qpid.py" )
    for module in ${list[@]}; do
        sed -i 's/\(^            node_name = \)msg_id$/\1"%s\/%s" % (msg_id, msg_id)/' $module
    done

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

