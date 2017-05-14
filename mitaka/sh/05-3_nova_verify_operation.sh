#!/bin/sh

export LANG=en_US.utf8

# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# List service components to verify successful launch and registration of each process:
echo
echo "** nova service-list"
echo

nova service-list

# List API endpoints in the Identity service to verify connectivity with the Identity service:
echo
echo "** nova endpoints"
echo

nova endpoints

# List images in the Image service catalog to verify connectivity with the Image service:
echo
echo "** nova image-list"
echo

nova image-list

echo
echo "Done."