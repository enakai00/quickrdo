install
url --url="http://192.168.200.1/Fedora19/"
network --bootproto=static --hostname=rdo03 --device=eth0 --gateway=192.168.200.1 --ip=192.168.200.13 --nameserver=192.168.200.1 --netmask=255.255.255.0 --activate
network --device=eth1 --onboot=no
rootpw passw0rd
graphical
firstboot --disable
keyboard jp106
lang en_US
reboot
timezone --isUtc Asia/Tokyo
bootloader --location=mbr
zerombr
clearpart --all --initlabel
part /boot --asprimary --fstype="ext4" --size=512
part swap --fstype="swap" --size=4096
part / --fstype="ext4" --grow --size=1
part pv.1 --size=20480
volgroup cinder-volumes pv.1

%packages
@core
@standard
%end
