#!/bin/bash
#location=http://10.250.214.2/centos7/
location=http://10.250.214.2/rhel7/
virt-install --name controller \
    --vcpus 4 --ram 4096 \
    --disk path=/var/lib/libvirt/images/controller.qcow2,size=64,sparse=false,format=qcow2  \
    --network bridge=virbr1,model=virtio \
    --network bridge=virbr2,model=virtio \
    --network bridge=virbr3,model=virtio \
    --network bridge=br0,model=virtio \
    --nographics \
    --cpu host \
    --os-variant rhel7 \
    --location ${location} \
    --initrd-inject=controller.ks \
    --extra-args="ks=file:/controller.ks console=ttyS0,115200"
