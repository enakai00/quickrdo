#!/bin/sh

function prep {
    setenforce 0
    sed -i.bak 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

    yum update -y
    yum install -y iptables-services
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service

    cat <<'EOF' > /etc/sysconfig/modules/openstack-neutron.modules
#!/bin/sh
modprobe -b bridge >/dev/null 2>&1
exit 0
EOF
    chmod u+x /etc/sysconfig/modules/openstack-neutron.modules 

    cat <<'EOF' > /etc/sysctl.d/bridge-nf-call
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-arptables = 1
EOF
}

function rdo_install {
    yum install -y http://rdo.fedorapeople.org/openstack/openstack-grizzly/rdo-release-grizzly.rpm
    yum install -y openstack-packstack

    # https://bugzilla.redhat.com/show_bug.cgi?id=977786
    qpidd_conf=/usr/lib/python2.*/site-packages/packstack/puppet/modules/qpid/templates/qpidd.conf.erb
    if grep -q cluster-mechanism $qpidd_conf; then
        yum install -y qpid-cpp-server-ha
        sed -i.bak 's/cluster-mechanism/ha-mechanism/' $qpidd_conf
    fi

    # http://openstack.redhat.com/forum/discussion/188/resolved-failed-allinone-installation-fedora-18
    yum install -y openstack-dashboard-2013.1.2-1.fc18 python-django-horizon-2013.1.2-1.fc18
    yum update -y openstack-dashboard python-django-horizon

    packstack --allinone --nagios-install=n --os-swift-install=n
    rc=$?

    if [[ $rc -ne 0 ]]; then
        echo "Packstack installation failed."
        exit $rc
    fi

    openstack-config --set /etc/quantum/quantum.conf DEFAULT ovs_use_veth True

    if virsh net-info default >/dev/null ; then
        virsh net-destroy default
        virsh net-autostart default --disable
    fi

    if ! grep -q -E '^systemctl restart qpidd$' /etc/rc.d/rc.local; then
        echo "systemctl restart qpidd" >> /etc/rc.d/rc.local
    fi

    # https://bugzilla.redhat.com/show_bug.cgi?id=978354
    yum install -y patch
    curl https://bugzilla.redhat.com/attachment.cgi?id=765551 > /tmp/securitygroups_db.py.patch
    cd /usr/lib/python2.*/site-packages/
    patch -p0 -Nsb < /tmp/securitygroups_db.py.patch
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

