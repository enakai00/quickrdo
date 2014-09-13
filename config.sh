#!/bin/sh -e

####
public="192.168.200.0/24"
gateway="192.168.200.1"
pool=("192.168.200.129" "192.168.200.254")
nameserver="192.168.200.1"
####

export LANG=en_US.utf8

function config_tenant {
    . /root/keystonerc_admin

    #
    # create project and users
    #
    keystone user-get snsapp-infra-admin && keystone user-delete snsapp-infra-admin
    keystone user-get snsapp-infra-user && keystone user-delete snsapp-infra-user
    keystone tenant-get SNSApp && keystone tenant-delete SNSApp

    keystone tenant-create --name SNSApp
    keystone user-create --name snsapp-infra-admin --pass passw0rd
    keystone user-create --name snsapp-infra-user --pass passw0rd
    keystone user-role-add --user snsapp-infra-admin --role admin --tenant SNSApp
    keystone user-role-add --user snsapp-infra-user --role _member_ --tenant SNSApp

    #
    # initialize neutron db
    #
    neutron_services=$(systemctl list-unit-files --type=service \
        | grep -E 'neutron\S+\s+enabled' | cut -d" " -f1)

    for s in ${neutron_services}; do systemctl stop $s; done
    mysqladmin -f drop ovs_neutron
    mysqladmin create ovs_neutron
    neutron-netns-cleanup
    for s in $neutron_services; do systemctl start $s; done
    sleep 5

    #
    # create external network
    #
    tenant=$(keystone tenant-list | awk '/ services / {print $2}')
    neutron net-create \
        --tenant-id $tenant Ext-Net --shared \
        --provider:network_type flat --provider:physical_network physnet1 \
        --router:external=True
    neutron subnet-create \
        --tenant-id $tenant --gateway ${gateway} --disable-dhcp \
        --allocation-pool start=${pool[0]},end=${pool[1]} \
        Ext-Net ${public}

    #
    # setup flavor
    #
    for id in $(nova flavor-list | awk '/^\| [0-9]+/{print $2}'); do
        nova flavor-delete $id
    done
    nova flavor-create --ephemeral 10 --rxtx-factor 1.0 standard.xsmall 100 1024 10 1
    nova flavor-create --ephemeral 10 --rxtx-factor 1.0 standard.small  101 2048 10 2
    nova flavor-create --ephemeral 50 --rxtx-factor 1.0 standard.medium 102 4096 50 2
    nova flavor-access-add 100 SNSApp
    nova flavor-access-add 101 SNSApp
    nova flavor-access-add 102 SNSApp

    tenant=$(keystone tenant-list | awk '/ SNSApp / {print $2}')
    nova quota-update --instances 20 $tenant
    nova quota-update --cores 40 $tenant
    nova quota-update --security-groups 20 $tenant
    nova quota-update --security-group-rules 40 $tenant
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

if ! ovs-vsctl list-ports br-ex | grep -q ${extnic}; then
    ovs-vsctl add-port br-ex ${extnic}
fi

if ! ovs-vsctl list-ports br-priv | grep -q ${privnic}; then
    ovs-vsctl add-port br-priv ${privnic}
fi

# Disable unnecessary services on controller
. ~/keystonerc_admin
if nova service-list | grep -qE "nova-compute +\| +$HOSTNAME +"; then
    nova service-disable $HOSTNAME nova-compute
fi
if cinder service-list | grep -qE "cinder-volume +\| +$HOSTNAME +"; then
    cinder service-disable $HOSTNAME cinder-volume
fi
if cinder service-list | grep -qE "cinder-backup +\| +$HOSTNAME +"; then
    cinder service-disable $HOSTNAME cinder-backup
fi

config_tenant 2>/dev/null

echo
echo "Configuration finished."

