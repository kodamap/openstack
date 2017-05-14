install
network --bootproto=static --hostname=storage1 --device=eth0 --gateway=10.250.240.1 --ip=10.250.240.14 --nameserver=8.8.8.8 --netmask=255.255.255.0 --activate
network --bootproto=static --device=eth1 --ip=192.168.102.14 --netmask=255.255.255.0 --activate
network --bootproto=static --device=eth2 --ip=192.168.103.14 --netmask=255.255.255.0 --activate
network --device=eth3 --onboot=no
rootpw password
selinux --permissive
text
firstboot --disable
keyboard jp106
lang en_US
reboot
timezone --isUtc Asia/Tokyo
bootloader --location=mbr
zerombr
clearpart --all --initlabel
part /boot --asprimary --fstype="xfs" --size=512 --ondisk=vda
part swap --fstype="swap" --size=4096 --ondisk=vda
part / --fstype="xfs" --grow --size=1 --ondisk=vda
%packages --nobase --ignoremissing
@core
%end
%post
yum -y update
%end
