#!/bin/sh -e

# this scripts is origined from
# https://github.com/josug-book1-materials/chapter05-10

LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <Controller IP>"
    exit 0
fi

controller=$1

    cat << EOF > ~/openrc
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=SNSApp
export OS_TENANT_NAME=SNSApp
export OS_USERNAME=snsapp-infra-user
export OS_PASSWORD=password
export OS_AUTH_URL=http://${controller}:5000/v3
export PS1='[\u@\h \W(snsapp-infra-user)]\$ '
EOF

source ~/openrc

neutron router-create ext-router
neutron router-gateway-set ext-router ext-net

neutron net-create work-net
neutron subnet-create --ip-version 4 --gateway 10.0.0.254 --name work-subnet --dns-nameserver 8.8.8.8 --dns-nameserver 8.8.4.4 work-net 10.0.0.0/24
neutron router-interface-add ext-router work-subnet

nova keypair-add key-for-step-server | tee key-for-stepserver.pem
chmod 600 key-for-stepserver.pem

neutron security-group-create --description "secgroup for step server"  sg-for-step-server
neutron security-group-rule-create --ethertype IPv4 --protocol icmp --remote-ip-prefix 0.0.0.0/0 sg-for-step-server
neutron security-group-rule-create --ethertype IPv4 --protocol tcp --port-range-min 22 --port-range-max 22 --remote-ip-prefix 0.0.0.0/0 sg-for-step-server

echo
echo "neutron security-group-list"
neutron security-group-list

echo
echo "neutron security-group-rule-lit"
neutron security-group-rule-lit
