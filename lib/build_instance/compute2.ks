install
network --bootproto=static --hostname=compute2 --device=eth0 --gateway=192.168.101.1 --ip=192.168.101.13 --nameserver=192.168.101.1 --netmask=255.255.255.0 --activate
network --device=eth1 --onboot=no
network --device=eth2 --onboot=no
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