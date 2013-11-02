#!/bin/sh -x

function pre_install {
    setenforce 0
    sed -i.bak 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

    yum update -y
    yum install -y http://rdo.fedorapeople.org/openstack/openstack-grizzly/rdo-release-grizzly.rpm
    yum install -y patch iptables-services

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
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
}

function post_install {
    privnic=$1

    if virsh net-info default >/dev/null ; then
        virsh net-destroy default
        virsh net-autostart default --disable
    fi

    if ! ovs-vsctl list-ports br-priv | grep -q ${privnic}; then
        ovs-vsctl add-port br-priv ${privnic}
    fi
}

## main

case $1 in
  pre)
    pre_install
    ;;
  post)
    post_install $2
    ;;
esac

