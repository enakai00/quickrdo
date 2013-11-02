#!/bin/sh

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

ssh-copy-id root@${compute_ip}
scp ./lib/prep_compute.sh root@${compute_ip}:/root/
ssh root@${compute_ip} "/root/prep_compute.sh pre"

echo
echo "Installing RDO with packstack...."
echo

./lib/genanswer.sh compute $compute_ip
packstack --answer-file=compute.txt
rc=$?

if [[ $rc -ne 0 ]]; then
    echo "Packstack installation failed."
    exit $rc
fi

echo
echo "Done. Now, rebooting the server..."
echo

ssh root@${compute_ip} reboot
res=""
while [[ $res != "Linux" ]]; do
    res=$(ssh -o "StrictHostKeyChecking no" root@${compute_ip} uname)
    sleep 5
done
ssh root@${compute_ip} "/root/prep_compute.sh post $privnic"

echo
echo "Done."
echo

