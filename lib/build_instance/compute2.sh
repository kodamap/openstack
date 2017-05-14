#!/bin/bash
#location=http://10.250.214.2/centos7/
location=http://10.250.214.2/rhel7/
virt-install --name compute2 \
    --vcpus 4 --ram 8192 \
    --disk path=/var/lib/libvirt/images/compute2.qcow2,size=64,sparse=false,format=qcow2 \
    --disk path=/var/lib/libvirt/images/compute2-1.qcow2,size=64,sparse=false,format=qcow2 \
    --disk path=/var/lib/libvirt/images/compute2-2.qcow2,size=20,sparse=false,format=qcow2 \
    --disk path=/var/lib/libvirt/images/compute2-3.qcow2,size=20,sparse=false,format=qcow2 \
    --network bridge=virbr1,model=virtio \
    --network bridge=virbr2,model=virtio \
    --network bridge=virbr3,model=virtio \
    --network bridge=br0,model=virtio \
    --nographics \
    --cpu host \
    --os-variant rhel7 \
    --location ${location} \
    --initrd-inject=compute2.ks \
    --extra-args="ks=file:/compute2.ks console=ttyS0,115200"
