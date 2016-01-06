#!/bin/sh

function pre_install {
    yum -y update
    yum -y install iptables-services
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service
}

function post_install {
    compute_ip=$1
    if cat /proc/cpuinfo | grep -E "^flags.+hypervisor" | grep -q -E "(vmx|svm)"; then
        openstack-config --set /etc/nova/nova.conf libvirt virt_type kvm
    fi
    openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_proxyclient_address $compute_ip
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

