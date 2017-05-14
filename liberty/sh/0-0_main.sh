#!/bin/sh -e

# controller node
controller=192.168.101.11
controller_tun=192.168.102.11

# conmpute1 / block node 1
compute1=192.168.101.12
compute1_tun=192.168.102.12

# compute2 / block node 2
compute2=192.168.101.13
compute2_tun=192.168.102.13

# ex_interface
ex_interface=eth3


./03-1_keystone_Install_and_configure.sh $controller
./03-2_keystone_create_service_entity_and_api_endpoint.sh $controller
./03-3_keystone_create_tenants_users_and_roles.sh $controller
./03-4_keystone_verify_operation.sh $controller
./03-5_OpenStack_client_environment_scripts.sh $controller
./04-1_glance_Install_and_configure.sh $controller
./04-2_glance_verify_operation.sh
./05-1_nova_Install_and_configure_contoller_node.sh $controller
./05-2_nova_Install_and_configure_compute_node.sh $controller $compute1
./05-2_nova_Install_and_configure_compute_node.sh $controller $compute2
./05-3_nova_verify_operation.sh
./06-1_neutron_Install_and_configure_contoller_node.sh  $controller $controller_tun $ex_interface
./06-2_neutron_Install_and_configure_compute_node.sh $controller $compute1 $compute1_tun $ex_interface
./06-2_neutron_Install_and_configure_compute_node.sh $controller $compute2 $compute2_tun $ex_interface
./07-1_horizon_Install_and_configure.sh $controller
./08-1_cinder_Install_and_configure_contoller_node.sh $controller
./08-2_cinder_Install_and_configure_storage_node.sh $controller $compute1
./08-2_cinder_Install_and_configure_storage_node.sh $controller $compute2