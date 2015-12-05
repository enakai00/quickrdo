#!/bin/sh -e

####
public="192.168.200.0/24"
gateway="192.168.200.1"
nameserver="8.8.8.8"
pool=("192.168.200.100" "192.168.200.199")
private=("192.168.101.0/24" "192.168.102.0/24")
####

export LANG=en_US.utf8

function config_tenant {
    . /root/keystonerc_admin

    #
    # Upload glance image
    #
    if ! glance image-list | grep "CentOS7" >/dev/null 2>&1; then
        glance --os-image-api-version 1 image-create --name "CentOS7" \
            --disk-format qcow2 --container-format bare --is-public true \
            --location http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2
    fi

    if ! glance image-list | grep "cirros" >/dev/null 2>&1; then
        glance --os-image-api-version 1 image-create --name "cirros" \
            --disk-format qcow2 --container-format bare --is-public true \
            --location http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
    fi

    #
    # create project and users
    #
    openstack user show demo_admin && openstack user delete demo_admin
    openstack user show demo_user && openstack user delete demo_user
    openstack project show demo && openstack project delete demo

    openstack project create demo
    openstack user create demo_admin --password passw0rd --project demo
    openstack user create demo_user --password passw0rd --project demo
    openstack role add --user demo_admin --project demo admin

    #
    # initialize neutron db
    #
    neutron_services=$(systemctl list-unit-files --type=service \
        | grep -E 'neutron\S+\s+enabled' | cut -d" " -f1)

    for s in ${neutron_services}; do systemctl stop $s; done
    mysqladmin -f drop neutron
    mysqladmin create neutron
    neutron-db-manage --config-file /etc/neutron/neutron.conf \
      --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade liberty

    neutron-netns-cleanup
    for s in $neutron_services; do systemctl start $s; done
    sleep 10

    #
    # create external network
    #
    tenant=$(openstack project list | awk '/ services / {print $2}')
    neutron net-create \
        --tenant-id $tenant ext-network --shared \
        --provider:network_type flat --provider:physical_network extnet \
        --router:external=True
    neutron subnet-create \
        --tenant-id $tenant --gateway ${gateway} --disable-dhcp \
        --allocation-pool start=${pool[0]},end=${pool[1]} \
        ext-network ${public}

    . /root/keystonerc_admin
    export OS_USERNAME=demo_user
    export OS_PASSWORD=passw0rd
    export OS_TENANT_NAME=demo
    #
    # create router
    #
    neutron router-create demo_router
    neutron router-gateway-set demo_router ext-network
    sleep 10

    #
    # create private networks
    #
    for (( i = 0; i < ${#private[@]}; ++i )); do
        name=$(printf "private%02d" $(( i + 1 )))
        subnet=${private[i]}
        neutron net-create ${name}
        neutron subnet-create --name ${name}-subnet \
            --dns-nameserver ${nameserver} ${name} ${subnet}
        neutron router-interface-add demo_router ${name}-subnet
    done

    #
    # configure security components
    #
    nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
    nova secgroup-add-rule default icmp 8 0 0.0.0.0/0
    if nova keypair-list | grep -q '^| mykey |'; then
        nova keypair-delete mykey
    fi
    nova keypair-add mykey > ~/mykey.pem
    chmod 600 ~/mykey.pem
    for i in $(seq 1 5); do
        neutron floatingip-create ext-network
    done
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

config_tenant 2>/dev/null

echo
echo "Configuration finished."

