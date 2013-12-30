#!/bin/sh

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
}

function pre_reboot {
    if cat /proc/cpuinfo | grep -E "^flags.+hypervisor" | grep -q -E "(vmx|svm)"; then
        openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_type kvm
    fi
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
  post1)
    pre_reboot
    ;;
  post2)
    post_install $2
    ;;
esac

