#!/bin/sh

function cleanup_all {
    services=$(systemctl list-unit-files | grep -E "(openstack|quantum).*\s+enabled" | cut -d" " -f1)
    for s in $services; do
        systemctl stop $s
        systemctl disable $s;
    done

    for x in $(virsh list --all | grep instance- | awk '{print $2}'); do
        virsh destroy $x
        virsh undefine $x
    done

    yum remove -y puppet "*ntp*" httpd "qpid-cpp-server*" \
        "*openstack*" "*quantum*" "*nova*" "*keystone*" \
        "*glance*" "*cinder*" openvswitch \
        mysql mysql-server "*memcache*" perl-DBI perl-DBD-MySQL \
        scsi-target-utils iscsi-initiator-utils \
        "rdo-release-*"

    for x in nova glance cinder keystone horizon quantum;do
        rm -rf /var/lib/$x /var/log/$x /etc/$x
    done

    rm -rf /etc/yum.repos.d/packstack_* /root/.my.cnf /var/lib/mysql \
        /etc/openvswitch /var/log/openvswitch 

    killall -9 dnsmasq tgtd httpd 

    if vgs cinder-volumes; then
        vgremove -f cinder-volumes
    fi

    for x in $(losetup -a | sed -e 's/:.*//g'); do
        losetup -d $x
    done

    rm -f /etc/rc.d/rc.local
}

# main

echo "This will completely uninstall all openstack-related components."
echo -n "Are you really sure? (yes/no) "
read answer
if [[ $answer == "yes" ]]; then
    cleanup_all 2>/dev/null
    echo "Finished."
else
    echo "Cancelled."
fi

