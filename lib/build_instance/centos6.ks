install
url --url="http://10.250.214.2/centos6/"
network --bootproto=dhcp --hostname=centos6 --device=eth0 --activate
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
part /boot --asprimary --fstype="ext4" --size=512 --ondisk=vda
part swap --fstype="swap" --size=4096 --ondisk=vda
part / --fstype="ext4" --grow --size=1 --ondisk=vda
%packages --nobase --ignoremissing
@core
%end

%post
yum -y update
cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8
EOF

yum -y install http://ftp.riken.jp/Linux/fedora/epel//6/x86_64/epel-release-6-8.noarch.rpm
yum -y install cloud-init
cp -p /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.org
sed -i -e 's/^disable_root: 1$/disable_root: 0/' /etc/cloud/cloud.cfg
sed -i -e 's/^ - set_hostname$/ - [ set_hostname, always]/' /etc/cloud/cloud.cfg
cat << EOF > /etc/sysconfig/network
NETWORKING=yes
NOZEROCONF=yes
EOF

cd /opt
rpm -ivh http://ftp-stud.hs-esslingen.de/pub/epel/6/i386/epel-release-6-8.noarch.rpm
yum install git parted cloud-utils
git clone https://github.com/flegmatik/linux-rootfs-resize.git
cd linux-rootfs-resize
./install
%end
