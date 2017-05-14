#!/bin/sh -e

export LANG=en_US.utf8

function get_netid () { neutron net-list | grep $1  | awk '{print $2}'; }

create_provider_network () {

  # change these parameters on your environment
  PROVIDER_NETWORK_CIDR="192.168.2.0/24"
  START_IP_ADDRESS="192.168.2.201"
  END_IP_ADDRESS="192.168.2.250"
  DNS_RESOLVER="8.8.8.8"
  PROVIDER_NETWORK_GATEWAY="192.168.2.1"

  # On the controller node, source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create the network:
  # The --shared option allows all projects to use the virtual network.
  # The --provider:physical_network provider and --provider:network_type flat options connect the flat
  # virtual network to the flat (native/untagged) physical network on the eth3 interface on the host
  echo
  echo "** neutron net-create provider"
  echo

  neutron net-create --shared --provider:physical_network provider --provider:network_type flat provider

  # To create a subnet on the external network
  # Create the subnet:
  # You should disable DHCP on this subnet because instances do not connect
  # directly to the external network and floating IP addresses require manual assignment.
  echo
  echo "** neutron subnet-create provider"
  echo

  neutron subnet-create --name provider-subnet --allocation-pool start=${START_IP_ADDRESS},end=${END_IP_ADDRESS} --dns-nameserver ${DNS_RESOLVER} --gateway ${PROVIDER_NETWORK_GATEWAY} provider ${PROVIDER_NETWORK_CIDR}

  echo
  echo "Done."
}

update_router () {

  # Self-service networks connect to provider networks using a virtual router that typically performs bidirectional NAT.
  # Each router contains an interface on at least one self-service network and a gateway on a provider network.
  # The provider network must include the router:external option to enable self-service routers to use it for connectivity
  # to external networks such as the Internet. The admin or other privileged user must include this option during network creation or add it later.
  # In this case, we can add it to the existing provider provider network.


  # On the controller node, source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Add the router: external option to the provider network:
  neutron net-update provider --router:external

}


# main

create_provider_network
update_router

echo
echo "Done."