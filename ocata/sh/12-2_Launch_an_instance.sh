#!/bin/sh -e

export LANG=en_US.utf8

function get_netid () { neutron net-list | grep $1  | awk '{print $2}'; }


create_selfservice_network () {

  SELFSERVICE_NETWORK_CIDR="192.168.1.0/24"
  DNS_RESOLVER="8.8.8.8"
  SELFSERVICE_NETWORK_GATEWAY="192.168.1.1"

  # On the controller node, source the demo credentials to gain access to user-only CLI commands:
  . ~/demo-openrc

  # Create the network:
  # Non-privileged users typically cannot supply additional parameters to this command.
  echo
  echo "** openstack network create demo-net"
  echo

  openstack network create demo-net

  # To create a subnet on the tenant network
  # Create the subnet:
  echo
  echo "** openstack subnet create demo-subnet"
  echo

  openstack subnet create --network demo-net \
    --dns-nameserver ${DNS_RESOLVER} --gateway ${SELFSERVICE_NETWORK_GATEWAY} \
    --subnet-range ${SELFSERVICE_NETWORK_CIDR} demo-subnet

}

create_router () {

  # Source the demo credentials to gain access to user-only CLI commands:
  source ~/demo-openrc

  # Create the router:
  openstack router create demo-router

  # Add the self-service network subnet as an interface on the router:
  neutron router-interface-add demo-router demo-subnet

  # Set a gateway on the provider network on the router:
  neutron router-gateway-set demo-router provider

  # Vefify Operation
  echo
  echo "ip netns"
  echo
  ip netns

  neutron router-port-list demo-router

}

generate_keypair () {

  # To generate a key pair
  # Most cloud images support public key authentication rather than conventional user name/password authentication.
  # Before launching an instance, you must generate a public/private key pair.
  #
  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/demo-openrc

  # Generate and add a key pair:
  echo
  echo "** Generating key pair...."
  echo

  openstack keypair create demo-key | tee demo-key.pem
  chmod 600 demo-key.pem
  ## ssh-keygen -q -N ""
  ## openstack keypair create --public-key ~/.ssh/id_rsa.pub demo-key.pem

  # Verify addition of the key pair:
  echo
  echo "** openstack keypair list"
  echo

  openstack keypair list

}

add_security_group () {

  # By default, the default security group applies to all instances and includes firewall rules that deny remote access to instances.
  # For Linux images such as CirrOS, we recommend allowing at least ICMP (ping) and secure shell (SSH).
  #
  # Permit ICMP (ping):
  echo
  echo "** Permit ICMP (ping):"
  echo

  openstack security group rule create --proto icmp default
  ## nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
  ## neutron security-group-rule-create --ethertype IPv4 --protocol icmp --remote-ip-prefix 0.0.0.0/0 default

  # Permit secure shell (SSH) access:
  echo
  echo "** Permit secure shell (SSH) access:"
  echo

  openstack security group rule create --proto tcp --dst-port 22 default
  ## nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
  ## neutron security-group-rule-create --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 --remote-ip-prefix 0.0.0.0/0 default

}

determine_instance_options () {

  # To launch an instance, you must at least specify the flavor, image name, network, security group, key,
  # and instance name.
  # On the controller node, source the demo credentials to gain access to user-only CLI commands:
  source ~/demo-openrc

  # A flavor specifies a virtual resource allocation profile which includes processor, memory, and storage.
  # List available flavors:
  echo
  echo "** openstack flavor list"
  echo

  openstack flavor list

  # List available images:
  echo
  echo "** openstack image list"
  echo

  openstack image list

  # List available networks:
  echo
  echo "** oenstack network list"
  echo

  openstack network list

  # List available security groups:
  echo
  echo "** openstack security group rule list default"
  echo

  openstack security group rule list default

}

launch_instance () {

  INSTANCE_NAME=$1

  . ~/demo-openrc
  # Launch the instance:
  echo
  echo "** openstack server create cirros"
  echo

  SELFSERVICE_NET_ID=`get_netid demo-net`

  openstack server create --flavor m1.nano --image cirros \
  --nic net-id=${SELFSERVICE_NET_ID} --security-group default \
  --key-name demo-key ${INSTANCE_NAME}

  # Check the status of your instance:
  echo
  echo "** openstack server list"
  echo

  openstack server list

  # To access your instance using a virtual console
  # Obtain a Virtual Network Computing (VNC) session URL for your instance and access it
  # from a web browser:
  echo
  echo "** Virtual Network Computing (VNC) session URL for your instance"
  echo

  ## nova get-vnc-console instance novnc
  openstack console url show ${INSTANCE_NAME}

  # To Access the instance remotely
  # Create a floating IP address on the provider virtual network:

  ## openstack ip floating create provider
  ## openstack ip floating add <floating ip address> <instance name>
  ## openstack server list

}

create_flavor () {

  echo
  echo "** creating m1.nano flavor..."
  echo

  source ~/admin-openrc
  openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano
  openstack flavor create --id 1 --vcpus 1 --ram 1024 --disk 10 m1.xsmall
  openstack flavor create --id 2 --vcpus 1 --ram 2048 --disk 20 m1.small
}


# main

if [[ -z $1 ]]; then
    echo "** Usage: $0 <instance name>"
    exit 1
fi

INSTANCE_NAME=$1

create_flavor
#create_selfservice_network
#create_router
generate_keypair
determine_instance_options
add_security_group
launch_instance ${INSTANCE_NAME}

echo
echo "Done."