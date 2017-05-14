#!/bin/sh

. ~/demo-openrc
neutron router-gateway-clear demo-router provider
neutron router-interface-delete demo-router demo-subnet
neutron router-delete demo-router
neutron port-list
neutron subnet-delete demo-subnet
neutron net-delete demo-net
neutron net-list

. ~/admin-openrc
neutron net-delete provider
neutron net-list
neutron subnet-list
