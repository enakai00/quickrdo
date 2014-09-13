#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "Usage: $0 <Compute node IP>"
    exit 0
fi

compute_ip=$1

az_num=""
while [[ -z $az_num ]]; do
    echo -n "Availability Zone Number: "
    read az_num
done

privnic=""
while [[ -z $privnic ]]; do
    echo -n "Private NIC: "
    read privnic
done

echo
echo "Doing preparations..."
echo

# Temporarily accept all incoming packets and modify iptables config file.
iptables -I INPUT 1 -j ACCEPT
controller_ip=$(cat compute.txt | awk -F'=' '/CONFIG_MYSQL_HOST=/{print $2}')
sed -i "s/^-A INPUT -s $controller_ip.*--dports 3260,8776 .*/-A INPUT -p tcp -m multiport --dports 3260,8776 -m comment --comment \"001 cinderapi incoming\" -j ACCEPT/" /etc/sysconfig/iptables
sed -i "s/^-A INPUT -s $controller_ip.*--dports 9292 .*/-A INPUT -p tcp -m multiport --dports 9292 -m comment --comment \"001 glanceapi incoming\" -j ACCEPT/" /etc/sysconfig/iptables
sed -i "s/^-A INPUT -s $controller_ip.*--dports 9696 .*/-A INPUT -p tcp -m multiport --dports 9696 -m comment --comment \"001 neutronapi incoming\" -j ACCEPT/" /etc/sysconfig/iptables
sed -i "s/\(^-A INPUT -s \)$controller_ip\(\/.*\)/&\n\1$compute_ip\2/" /etc/sysconfig/iptables

ssh-copy-id root@${compute_ip}
scp ./lib/prep_compute.sh root@${compute_ip}:/root/
scp ./lib/*patch root@${compute_ip}:/root/
ssh root@${compute_ip} "/root/prep_compute.sh pre"

echo
echo "Installing RDO with packstack...."
echo

./lib/genanswer.sh compute $compute_ip
packstack --answer-file=compute.txt

echo
echo "Done. Now, rebooting the server..."
echo

ssh root@${compute_ip} "/root/prep_compute.sh post1 $az_num"
ssh root@${compute_ip} reboot || :
res=""
while [[ $res != "Linux" ]]; do
    res=$(ssh -o "StrictHostKeyChecking no" root@${compute_ip} uname) || :
    sleep 5
done
ssh root@${compute_ip} "/root/prep_compute.sh post2 $privnic"

compute_host=$(ssh root@${compute_ip} hostname)
. ~/keystonerc_admin
cinder service-disable $compute_host cinder-scheduler
nova aggregate-create ag$az_num az$az_num
id=$(nova aggregate-list | grep " ag$az_num " | cut -d"|" -f2)
nova aggregate-add-host $id $compute_host

echo
echo "Done."
echo

