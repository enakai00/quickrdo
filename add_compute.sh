#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "Usage: $0 <Compute node IP>"
    exit 0
fi

compute_ip=$1

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
controller_ip=$(cat compute.txt | awk -F'=' '/CONFIG_CONTROLLER_HOST=/{print $2}')
sed -i "s/\(^-A INPUT -s \)$controller_ip\(\/.*\)/&\n\1$compute_ip\2/" /etc/sysconfig/iptables

ssh-copy-id root@${compute_ip}
scp ./lib/prep_compute.sh root@${compute_ip}:/root/
ssh root@${compute_ip} "/root/prep_compute.sh pre"

echo
echo "Installing OPS with packstack...."
echo

./lib/genanswer.sh compute $compute_ip
packstack --answer-file=compute.txt

echo
echo "Done. Now, rebooting the server..."
echo

ssh root@${compute_ip} "/root/prep_compute.sh post1 $compute_ip"
ssh root@${compute_ip} reboot || :
res=""
while [[ $res != "Linux" ]]; do
    res=$(ssh -o "StrictHostKeyChecking no" root@${compute_ip} uname) || :
    sleep 5
done
ssh root@${compute_ip} "/root/prep_compute.sh post2 $privnic"

echo
echo "Done."
echo

