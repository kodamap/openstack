install
url --url="http://10.250.214.2/centos7/"
network --bootproto=dhcp --hostname=centos7 --device=eth0 --activate
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
cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8
EOF

yum -y install http://download.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-7.noarch.rpm
yum -y install cloud-init
cp -p /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.org
sed -i -e 's/^disable_root: 1$/disable_root: 0/' /etc/cloud/cloud.cfg
sed -i -e 's/^ - set_hostname$/ - [ set_hostname, always]/' /etc/cloud/cloud.cfg
cat << EOF > /etc/sysconfig/network
NETWORKING=yes
NOZEROCONF=yes
EOF

yum -y install cloud-utils-growpart

cp -p /etc/default/grub /etc/default/grub.org
sed -i -e 's/^GRUB_CMDLINE_LINUX=*.*/GRUB_CMDLINE_LINUX=\"crashkernel=auto console=tty0 console=ttyS0,115200n8 no_timer_check\"/' /etc/default/grub 
grub2-mkconfig -o /boot/grub2/grub.cfg
%end
