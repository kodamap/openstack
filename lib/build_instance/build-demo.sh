#!/bin/bash
if [[ $# -ne 1 ]];
then
   echo "Usage : $0 <csv>"
   exit 1;
fi

file=$1
vcpus=2
ram=4096
location=http://10.250.214.2/centos7/

function makeks () {
  host=$1
  ip=$2
  netmask=$3
  gateway=$4
  dns=$5

  cat << EOF > ${host}.ks
install
url --url=${location}
network --bootproto=static --hostname=${host} --device=eth0 --gateway=${gateway} --ip=${ip} --nameserver=${dns} --netmask=${netmask} --activate
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
EOF
}

function buildvm () {
  host=$1
  vcpus=$2
  ram=$3
  location=$4

  virt-install --name ${host} \
    --vcpus ${vcpus} --ram ${ram} \
    --disk path=/var/lib/libvirt/images/${host}.qcow2,size=40,sparse=false,format=qcow2  \
    --network bridge=br0,model=virtio \
    --nographics \
    --cpu host \
    --os-variant rhel7 \
    --location ${location} \
    --initrd-inject=${host}.ks \
    --extra-args="ks=file:/${host}.ks console=ttyS0,115200"
}

for LINE in `cat ${file}`
do
  host=`echo $LINE | awk -F, '{print $1}'`
  ip=`echo $LINE | awk -F, '{print $2}'`
  netmask=`echo $LINE | awk -F, '{print $3}'`
  gateway=`echo $LINE | awk -F, '{print $4}'`
  dns=`echo $LINE | awk -F, '{print $5}'`

  echo "*******"
  echo ${host}
  echo ${ip}
  echo ${netmask}
  echo ${gateway}
  echo ${dns}
  echo "*******"

  makeks ${host} ${ip} ${netmask} ${gateway} ${dns}
  buildvm ${host} ${vcpus} ${ram} ${location} &
  sleep 5;
 
done

