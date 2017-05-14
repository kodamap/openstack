#!/bin/sh

export LANG=en_US.utf8

# Install the package
yum -y -q install wget

# In each client environment script, configure the Image service client to use API version 2.0:
if ! grep "OS_IMAGE_API_VERSION=2" ~/admin-openrc > /dev/null ; then
    echo "export OS_IMAGE_API_VERSION=2" | tee -a ~/admin-openrc ~/demo-openrc
fi

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

glance image-create --name "cirros-0.3.4-x86_64" --file /tmp/images/cirros-0.3.4-x86_64-disk.img \
  --disk-format qcow2 --container-format bare --visibility public --progress

sleep 1;

# Confirm upload of the image and validate attributes:
echo
echo "** glance image-list"
echo

glance image-list

echo
echo "Done."