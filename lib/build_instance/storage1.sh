#!/bin/bash
location=http://10.250.240.2/centos7/
virt-install --name storage1 \
    --vcpus 2 --ram 8192 \
    --disk path=/var/lib/libvirt/images/storage1.qcow2,size=64,sparse=false,format=qcow2 \
    --disk path=/var/lib/libvirt/images2/storage1-cinder.qcow2,size=400,sparse=false,format=qcow2 \
    --network bridge=br240,model=virtio \
    --network bridge=virbr2,model=virtio \
    --network bridge=virbr3,model=virtio \
    --network bridge=br241,model=virtio \
    --nographics \
    --cpu host \
    --os-variant rhel7 \
    --location ${location} \
    --initrd-inject=storage1.ks \
    --extra-args="ks=file:/storage1.ks console=ttyS0,115200"
