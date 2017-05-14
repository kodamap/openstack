#!/bin/bash
if [[ $# -ne 1 ]];
then
   echo "Usage : $0 <csv>"
   exit 1;
fi

file=$1

for LINE in `cat ${file}`
do
  host=`echo $LINE | awk -F, '{print $1}'`
  virsh destroy ${host}
  virsh undefine ${host}
  rm -rf /var/lib/libvirt/images/${host}.qcow2
done
