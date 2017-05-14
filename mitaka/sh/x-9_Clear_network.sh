#!/bin/sh

LANG=en_US.utf8

if [[ $# -ne 1 ]]; then
    echo "** Usage: $0 <TENANT_NAME name>"
    exit 1
fi

TENANT_NAME=$1

source ~/${TENANT_NAME}-openrc


neutron router-gateway-clear ${TENANT_NAME}-router

neutron router-interface-delete ${TENANT_NAME}-router ${TENANT_NAME}-subnet
neutron subnet-delete ${TENANT_NAME}-subnet
neutron net-delete ${TENANT_NAME}-net

neutron router-interface-delete ${TENANT_NAME}-router ${TENANT_NAME}-subnet2
neutron subnet-delete ${TENANT_NAME}-subnet2
neutron net-delete ${TENANT_NAME}-net2

neutron router-delete ${TENANT_NAME}-router


