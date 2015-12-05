#!/bin/sh

function pre_install {
    subscription-manager repos --disable=*
    subscription-manager repos \
        --enable=rhel-7-server-rpms \
        --enable=rhel-7-server-optional-rpms \
        --enable=rhel-7-server-extras-rpms \
        --enable=rhel-7-server-openstack-7.0-rpms

    yum -y install yum-plugin-priorities yum-utils
    for repo in rhel-7-server-openstack-7.0-rpms \
                rhel-7-server-rpms \
                rhel-7-server-optional-rpms \
                rhel-7-server-extras-rpms; do
        yum-config-manager --enable $repo --setopt="$repo.priority=1"
    done

    yum -y update
    yum -y install iptables-services
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl start iptables.service
    systemctl enable iptables.service
}

function pre_reboot {
    compute_ip=$1
    if cat /proc/cpuinfo | grep -E "^flags.+hypervisor" | grep -q -E "(vmx|svm)"; then
        openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_type kvm
    fi
    openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_proxyclient_address $compute_ip
}

function post_install {
    privnic=$1
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
    pre_reboot $2
    ;;
  post2)
    post_install $2
    ;;
esac

