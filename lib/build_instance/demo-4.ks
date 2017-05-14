install
url --url=http://10.250.214.2/centos7/
network --bootproto=static --hostname=demo-4 --device=eth0 --gateway=10.250.214.1 --ip=10.250.214.104 --nameserver=8.8.8.8 --netmask=255.255.255.0 --activate
rootpw password
text
firstboot --disable
firewall --disabled
selinux --disabled
keyboard jp106
lang en_US
reboot --eject
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
echo "nameserver 8.8.8.8" >>  /etc/resolv.conf
%end
