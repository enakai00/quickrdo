#!/bin/sh -e

export LANG=en_US.utf8

function prep {
    setenforce 0
    sed -i.bak 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

    yum update -y
    yum install -y patch
    yum install -y iptables-services
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service
}

function rdo_install {
    yum install -y http://rdo.fedorapeople.org/openstack/EOL/openstack-grizzly/rdo-release-grizzly-3.noarch.rpm
    sed -i 's/openstack\/openstack-grizzly/openstack\/EOL\/openstack-grizzly/' /etc/yum.repos.d/rdo-release.repo
    yum install -y openstack-packstack-2013.1.1-0.20.dev642.fc19.noarch

    # https://bugzilla.redhat.com/show_bug.cgi?id=977786
    qpidd_conf=/usr/lib/python2.*/site-packages/packstack/puppet/modules/qpid/templates/qpidd.conf.erb
    if grep -q cluster-mechanism $qpidd_conf; then
        yum install -y qpid-cpp-server-ha
        sed -i.bak 's/cluster-mechanism/ha-mechanism/' $qpidd_conf
    fi

    patch_path=$(pwd)/lib
    pushd /usr/lib/python2.7/site-packages/
    patch -p0 -Nsb packstack/plugins/puppet_950.py < $patch_path/puppet_950.py.patch 
    patch -p0 -Nsb packstack/plugins/prescript_000.py < $patch_path/prescript_000.py.patch
    popd

    ./lib/genanswer.sh controller
    packstack --answer-file=controller.txt
    openstack-config --set /etc/quantum/quantum.conf DEFAULT ovs_use_veth True
    openstack-config --set /etc/quantum/plugin.ini OVS network_vlan_ranges physnet1,physnet2:100:199
    openstack-config --set /etc/quantum/plugin.ini OVS bridge_mappings physnet1:br-ex,physnet2:br-priv

    if virsh net-info default | grep -q -E "Active: *yes"; then
        virsh net-destroy default
        virsh net-autostart default --disable
    fi

    # https://bugzilla.redhat.com/show_bug.cgi?id=978354
    curl https://bugzilla.redhat.com/attachment.cgi?id=765551 > /tmp/securitygroups_db.py.patch
    cd /usr/lib/python2.*/site-packages/
    patch -p0 -Nsb < /tmp/securitygroups_db.py.patch

    systemctl stop openstack-nova-compute.service 
    systemctl disable openstack-nova-compute.service 

    # https://bugzilla.redhat.com/show_bug.cgi?id=1012001
    if [[ -f /etc/qpidd.conf && -f /etc/qpid/qpidd.conf ]]; then
        cp -f /etc/qpidd.conf /etc/qpid/qpidd.conf
    fi

    cat <<'EOF' >/etc/cron.daily/token_creanup.sh
#!/bin/bash

/usr/bin/mysql keystone -e "delete from token where now() > expires;" 2>&1 | logger -t "token_cleanup"
EOF
    chmod u+x /etc/cron.daily/token_creanup.sh
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

