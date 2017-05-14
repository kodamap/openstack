#!/bin/sh -e

export LANG=en_US.utf8

echo
echo "** Configuration started."
echo

# In each client environment script, configure the Block Storage client to use API version 2.0:
RC=/root/admin-openrc

if ! grep "OS_VOLUME_API_VERSION=2" ${RC} ; then

    echo "export OS_VOLUME_API_VERSION=2" | tee -a ${RC}
    
fi

RC=/root/demo-openrc

if ! grep "OS_VOLUME_API_VERSION=2" ${RC} ; then

    echo "export OS_VOLUME_API_VERSION=2" | tee -a ${RC}
    
fi

RC=/root/test-openrc

if ! grep "OS_VOLUME_API_VERSION=2" ${RC} ; then

    echo "export OS_VOLUME_API_VERSION=2" | tee -a ${RC}
    
fi

# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

#List service components to verify successful launch of each process:
echo
echo "cinder service-list"
echo

cinder service-list

# Source the demo credentials to perform the following steps as a non-administrative project:
source ~/demo-openrc

# Create a 1 GB volume:
echo
echo "cinder create --name demo-volume1 1 --availability-zone az1/az2"
echo

cinder create --name demo-volume1 1 --availability-zone az1
cinder create --name demo-volume2 1 --availability-zone az2

# Verify creation and availability of the volume:
echo
echo "cinder list"
echo

cinder list

# Source the test credentials to perform the following steps as a non-administrative project:
source ~/test-openrc

# Create a 1 GB volume:
echo
echo "cinder create --name test-volume1 1 --availability-zone az1/az2"
echo

cinder create --name test-volume1 1 --availability-zone az1
cinder create --name test-volume2 1 --availability-zone az2

# Verify creation and availability of the volume:
echo
echo "cinder list"
echo

cinder list

echo
echo "** Done."
echo