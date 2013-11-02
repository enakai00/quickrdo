#!/bin/sh

####
public="192.168.199.0/24"
gateway="192.168.199.1"
nameserver="192.168.199.1"
pool=("192.168.199.100" "192.168.199.199")
private=("192.168.101.0/24")
####

function config_tenant {
    . /root/keystonerc_admin

    #
    # Upload glance image
    #
    if ! glance image-show "Fedora19" >/dev/null 2>&1; then
        glance image-create --name "Fedora19" \
            --disk-format qcow2 --container-format bare --is-public true \
            --copy-from http://cloud.fedoraproject.org/fedora-19.x86_64.qcow2
    fi
    #
    # create project and users
    #
    keystone user-get demo_admin && keystone user-delete demo_admin
    keystone user-get demo_user && keystone user-delete demo_user
    keystone tenant-get demo && keystone tenant-delete demo

    keystone tenant-create --name demo
    keystone user-create --name demo_admin --pass passw0rd
    keystone user-create --name demo_user --pass passw0rd
    keystone user-role-add --user demo_admin --role admin --tenant demo
    keystone user-role-add --user demo_user --role Member --tenant demo

    #
    # initialize quantum db
    #
    quantum_services=$(systemctl list-unit-files --type=service \
        | grep -E 'quantum\S+\s+enabled' | cut -d" " -f1)

    for s in ${quantum_services}; do systemctl stop $s; done
    mysqladmin -f drop ovs_quantum
    mysqladmin create ovs_quantum
    quantum-netns-cleanup
    for s in $quantum_services; do systemctl start $s; done
    sleep 5

    #
    # create external network
    #
    tenant=$(keystone tenant-list | awk '/ services / {print $2}')
    quantum net-create \
        --tenant-id $tenant ext-network --shared \
        --provider:network_type flat --provider:physical_network physnet1 \
        --router:external=True
    quantum subnet-create \
        --tenant-id $tenant --gateway ${gateway} --disable-dhcp \
        --allocation-pool start=${pool[0]},end=${pool[1]} \
        ext-network ${public}

    #
    # create router
    #
    tenant=$(keystone tenant-list|awk '/ demo / {print $2}')
    quantum router-create --tenant-id $tenant demo_router
    quantum router-gateway-set demo_router ext-network

    #
    # create private networks
    #
    for (( i = 0; i < ${#private[@]}; ++i )); do
        name=$(printf "private%02d" $(( i + 1 )))
        vlanid=$(printf "%03d" $(( i + 101 )))
        subnet=${private[i]}
        quantum net-create \
            --tenant-id $tenant ${name} \
            --provider:network_type vlan \
            --provider:physical_network physnet2 \
            --provider:segmentation_id ${vlanid}
        quantum subnet-create \
            --tenant-id $tenant --name ${name}-subnet \
            --dns-nameserver ${nameserver} ${name} ${subnet}
        quantum router-interface-add demo_router ${name}-subnet
    done

    #
    # configure security components
    #
    . /root/keystonerc_admin
    export OS_USERNAME=demo_user
    export OS_PASSWORD=passw0rd
    export OS_TENANT_NAME=demo
    nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
    nova secgroup-add-rule default icmp 8 0 0.0.0.0/0
    if nova keypair-list | grep -q '^| mykey |'; then
        nova keypair-delete mykey
    fi
    nova keypair-add mykey > ~/mykey.pem
    chmod 600 ~/mykey.pem
    for i in $(seq 1 5); do
        quantum floatingip-create ext-network
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

config_tenant # 2>/dev/null

echo
echo "Configuration finished."

