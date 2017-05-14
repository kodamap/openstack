#!/bin/sh

export LANG=en_US.utf8

# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# Add the compute node to the cell database
echo
echo "** openstack hypervisor list"
echo

openstack hypervisor list

# Discover compute hosts:
echo
echo "** nova-manage cell_v2 discover_hosts --verbose"
echo

su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova

sleep 5;

# Note
# When you add new compute nodes, you must run nova-manage cell_v2 discover_hosts on the controller node to register those new compute nodes. 
# Alternatively, you can set an appropriate interval in /etc/nova/nova.conf:
#
# [scheduler]
# discover_hosts_in_cells_interval = 300

# List service components to verify successful launch and registration of each process:
echo
echo "** openstack compute service list"
echo

openstack compute service list

# List API endpoints in the Identity service to verify connectivity with the Identity service:
echo
echo "** openstack catalog list"
echo

openstack catalog list

# List images in the Image service catalog to verify connectivity with the Image service:
echo
echo "** openstack image list"
echo

openstack image list

echo
echo "Done."