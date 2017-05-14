#!/bin/sh -e

export LANG=en_US.utf8

# change these parameters on your environment
EXTERNAL_NETWORK_CIDR="10.250.240.0/24"
FLOATING_IP_START="10.250.240.201"
FLOATING_IP_END="10.250.240.220"
EXTERNAL_NETWORK_GATEWAY="10.250.240.1"

# To create the external network
# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# Create the network:
#
# Like a physical network, a virtual network requires a subnet assigned to it.
# The external network shares the same subnet and gateway associated with the physical network
# connected to the external interface on the network node.
# You should specify an exclusive slice of this subnet for router and floating IP addresses to
# prevent interference with other devices on the external network.
echo
echo "** neutron net-create ext-net"
echo

neutron net-create ext-net --router:external \
  --provider:physical_network external --provider:network_type flat

# To create a subnet on the external network
# Create the subnet:
# You should disable DHCP on this subnet because instances do not connect
# directly to the external network and floating IP addresses require manual assignment.
echo
echo "** neutron subnet-create ext-net"
echo

neutron subnet-create ext-net ${EXTERNAL_NETWORK_CIDR} --name ext-subnet \
  --allocation-pool start=${FLOATING_IP_START},end=${FLOATING_IP_END} \
  --disable-dhcp --gateway ${EXTERNAL_NETWORK_GATEWAY}

echo
echo "Done."