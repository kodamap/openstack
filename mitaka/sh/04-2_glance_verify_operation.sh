#!/bin/sh

export LANG=en_US.utf8

# Install the package
yum -y install wget

# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# Create a temporary local directory:
mkdir /tmp/images

# Download the source image into it:
echo
echo "getting image cirros-0.3.4-x86_64-disk.img"
echo

wget -P /tmp/images http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img

# Upload the image to the Image service using the QCOW2 disk format, bare container format,
# and public visibility so all projects can access it:
echo
echo "** glance image create  - cirros-0.3.4-x86_64 -"
echo

openstack image create "cirros" \
  --file /tmp/images/cirros-0.3.4-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --public

sleep 1;

# Confirm upload of the image and validate attributes:
echo
echo "** openstack image list"
echo

openstack image list
# glance image-list

echo
echo "Done."
