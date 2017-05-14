#!/bin/sh -e

export LANG=en_US.utf8

function get_uuid () {
    NET=$1
    neutron net-show ${NET} | grep " id " | awk '{print $4}';
}

create_keypair () {

    TENANT_NAME=$1
    source ~/${TENANT_NAME}-openrc

    # To Create Key pair
    echo
    echo "** creating key pair..."
    echo

    nova keypair-add ${TENANT_NAME}-key | tee ${TENANT_NAME}-key.pem
    chmod 600 ${TENANT_NAME}-key.pem

}

create_secgroup_rule () {

    TENANT_NAME=$1
    source ~/${TENANT_NAME}-openrc

    # To access your instance remotely
    # Add rules to the default security group:
    #
    # Permit ICMP (ping):

    echo
    echo "** Permit ICMP (ping):"
    echo

    nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
    # neutron security-group-rule-create --ethertype IPv4 --protocol icmp --remote-ip-prefix 0.0.0.0/0 default


    # Permit secure shell (SSH) access:
    echo
    echo "** Permit secure shell (SSH) access:"
    echo

    nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
    # neutron security-group-rule-create --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 --remote-ip-prefix 0.0.0.0/0 default
}

launch_instance () {

    #
    # create a instance
    #

    echo
    echo "** Launching a instance..."
    echo

    TENANT_NAME=$1
    NET_ID=$2
    INSTANCE_NAME=$3

    source ~/${TENANT_NAME}-openrc

    IMAGE=cirros-0.3.4-x86_64
    # IMAGE=cirros

    if [[ ${AZ} = "" ]]; then
    nova boot --flavor m1.tiny --image ${IMAGE} \
        --nic net-id=${NET_ID} \
        --security-group default --key-name ${TENANT_NAME}-key ${INSTANCE_NAME}
    else
    nova boot --flavor m1.tiny --image ${IMAGE} \
        --nic net-id=${NET_ID} \
        --security-group default --key-name ${TENANT_NAME}-key ${INSTANCE_NAME} \
        --availability-zone=${AZ}
    fi
}

create_project_network () {

    #
    # create a project network
    #

    TENANT_NAME=$1
    echo
    echo "** creating a ${TENANT_NAME} project network ..."
    echo

    # To create the tenant network
    # Source the ${TENANT_NAME} credentials to gain access to user-only CLI commands:
    source ~/${TENANT_NAME}-openrc

    # Create the network:
    # Like the external network, your tenant network also requires a subnet attached to it.
    # You can specify any valid subnet because the architecture isolates tenant networks.
    # By default, this subnet uses DHCP so your instances can obtain IP addresses.
    echo
    echo "** neutron net-create ${TENANT_NAME}-net"
    echo

    neutron net-create ${TENANT_NAME}-net

    # To create a subnet on the tenant network
    # Create the subnet:
    echo
    echo "** neutron subnet-create ${TENANT_NAME}-net"
    echo

    neutron subnet-create ${TENANT_NAME}-net ${TENANT_NETWORK_CIDR} \
      --name ${TENANT_NAME}-subnet --dns-nameserver ${DNS_RESOLVER} \
      --gateway ${TENANT_NETWORK_GATEWAY}

    # To create a router on the tenant network and attach the external and tenant networks to it
    # Create the router:
    echo
    echo "** neutron router-create ${TENANT_NAME}-router"
    echo

    neutron router-create ${TENANT_NAME}-router

    # Attach the router to the ${TENANT_NAME} tenant subnet:
    echo
    echo "** neutron router-interface-add ${TENANT_NAME}-router ${TENANT_NAME}-subnet"
    echo

    neutron router-interface-add ${TENANT_NAME}-router ${TENANT_NAME}-subnet

    # Attach the router to the external network by setting it as the gateway:
    echo
    echo "** neutron router-gateway-set ${TENANT_NAME}-router provider"
    echo

    neutron router-gateway-set ${TENANT_NAME}-router provider
}

create_project () {

    #
    # create project and users
    #

    source ~/admin-openrc

    TENANT_NAME=$1

    echo
    echo "** Creating ${TENANT_NAME} project..."
    echo

    openstack user show ${TENANT_NAME} && openstack user delete ${TENANT_NAME}
    openstack project show ${TENANT_NAME} && openstack project delete ${TENANT_NAME}

    openstack project create --description "${TENANT_NAME} Project" ${TENANT_NAME}

    # Create the ${TENANT_NAME} user:
    echo
    echo "** Creating the ${TENANT_NAME} user..."
    echo

    openstack user create --password ${TENANT_NAME} ${TENANT_NAME}

    # Add the user role to the ${TENANT_NAME} project and user:
    echo
    echo "** Adding the user role to the ${TENANT_NAME} project and user..."
    echo

    openstack role add --project ${TENANT_NAME} --user ${TENANT_NAME} user

    # Openrc Script
    cat << EOF > ~/${TENANT_NAME}-openrc
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=${TENANT_NAME}
export OS_TENANT_NAME=${TENANT_NAME}
export OS_USERNAME=${TENANT_NAME}
export OS_PASSWORD=${TENANT_NAME}
export OS_AUTH_URL=http://${controller}:5000/v3
export PS1='[\u@\h \W(${TENANT_NAME})]\$ '
EOF

    echo
    echo "** ~/${TENANT_NAME}-openrc"
    echo
    cat ~/${TENANT_NAME}-openrc

}

# main

if [[ $# -lt 2 ]]; then
    echo "** Usage: $0 <controller node IP> <tenant name>"
    exit 1
fi

controller=$1
TENANT_NAME=$2
AZ=$3

TENANT_NETWORK_CIDR="192.168.1.0/24"
DNS_RESOLVER="8.8.8.8"
TENANT_NETWORK_GATEWAY="192.168.1.1"

echo
echo "** Configuration(${TENANT_NAME}) started."
echo


# To create project
create_project ${TENANT_NAME}

# To create project network
create_project_network ${TENANT_NAME}

# To create key pair
create_keypair ${TENANT_NAME}

# To create security group tule to default
create_secgroup_rule ${TENANT_NAME}

# To get net id
NET_ID=`get_uuid ${TENANT_NAME}-net`

# To Launch ${TENANT_NAME} instance
launch_instance ${TENANT_NAME} ${NET_ID} ${TENANT_NAME}-instance1

echo
echo "** Done."
echo
