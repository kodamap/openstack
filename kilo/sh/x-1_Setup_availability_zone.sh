#!/bin/sh -e

# this script originateed in
# https://github.com/josug-book1-materials/quickrdo

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <Compute IP>"
    exit 0
fi

compute_ip=$1

az_num=""
while [[ -z $az_num ]]; do
    echo -n "Availability Zone Number: "
    read az_num
done

echo
echo "** Configuration(Availablity Zone) started."
echo


# on controller node
openstack-config --set /etc/nova/nova.conf DEFAULT cinder_cross_az_attach False
# openstack-config --set --existing /etc/swift/proxy-server.conf filter:keystone operator_roles 'admin, SwiftOperator, _member_'
openstack-config --set /etc/nova/nova.conf DEFAULT default_availability_zone az1
openstack-config --set /etc/nova/nova.conf DEFAULT allow_resize_to_same_host true

for service in `systemctl list-unit-files --type=service |grep nova |grep enable | awk '{print $1}'`
do
    echo "systemctl restart ${service}..."
    systemctl restart ${service}
done

# on compute node
ssh root@${compute_ip} "openstack-config --set /etc/cinder/cinder.conf DEFAULT default_availability_zone az$az_num"
ssh root@${compute_ip} "openstack-config --set /etc/cinder/cinder.conf DEFAULT storage_availability_zone az$az_num"
ssh root@${compute_ip} "systemctl restart openstack-cinder-volume.service"

# on controller node
source ~/admin-openrc
compute_host=$(ssh root@${compute_ip} hostname)
nova aggregate-create ag$az_num az$az_num
id=$(nova aggregate-list | grep " ag$az_num " | cut -d"|" -f2)
nova aggregate-add-host $id $compute_host

# verify operation
nova service-list

echo
echo "** Configuration finished."
echo