#!/bin/sh -e

# controller node
controller=10.250.240.41

# network node node
network=10.250.240.42
network_tun=10.250.241.42
ex_interface=eno50336512

# conmpute / block node 1
compute1=10.250.240.43
compute1_tun=10.250.241.43

# compute / block node 2
compute2=10.250.240.44
compute2_tun=10.250.241.44


echo "** 03-1_keystone_Install_and_configure.sh ${controller}"
./03-1_keystone_Install_and_configure.sh ${controller} > $0.log

echo "** 03-2_keystone_create_service_entity_and_api_endpoint.sh ${controller}"
./03-2_keystone_create_service_entity_and_api_endpoint.sh ${controller} >> $0.log

echo "** 03-3_keystone_create_tenants_users_and_roles.sh ${controller}"
./03-3_keystone_create_tenants_users_and_roles.sh ${controller} >> $0.log

echo "** 03-4_OpenStack_client_environment_scripts.sh ${controller}"
./03-4_OpenStack_client_environment_scripts.sh ${controller} >> $0.log

echo "** 04-1_glance_Install_and_configure.sh ${controller}"
./04-1_glance_Install_and_configure.sh ${controller} >> $0.log

echo "** 04-2_glance_verify_operation.sh"
./04-2_glance_verify_operation.sh >> $0.log

echo "** 05-1_nova_Install_and_configure_contoller_node.sh ${controller}"
./05-1_nova_Install_and_configure_contoller_node.sh ${controller} >> $0.log

echo "** 05-2_nova_Install_and_configure_compute_node.sh ${controller} ${compute1}"
./05-2_nova_Install_and_configure_compute_node.sh ${controller} ${compute1} >> $0.log

echo "** 05-2_nova_Install_and_configure_compute_node.sh ${controller} ${compute2}"
./05-2_nova_Install_and_configure_compute_node.sh ${controller} ${compute2} >> $0.log

echo "** 05-3_nova_verify_operation.sh"
./05-3_nova_verify_operation.sh >> $0.log

echo "** 06-1_neutron_Install_and_configure_contoller_node.sh ${controller}"
./06-1_neutron_Install_and_configure_contoller_node.sh ${controller} >> $0.log

echo "** 06-2_neutron_Install_and_configure_network_node.sh ${controller} ${network} ${network_tun} ${ex_interface}"
./06-2_neutron_Install_and_configure_network_node.sh ${controller} ${network} ${network_tun} ${ex_interface} >> $0.log

echo "** 06-3_neutron_Install_and_configure_compute_node.sh ${controller} ${compute1} ${compute1_tun}"
./06-3_neutron_Install_and_configure_compute_node.sh ${controller} ${compute1} ${compute1_tun} >> $0.log

echo "** 06-3_neutron_Install_and_configure_compute_node.sh ${controller} ${compute2} ${compute2_tun}"
./06-3_neutron_Install_and_configure_compute_node.sh ${controller} ${compute2} ${compute2_tun} >> $0.log

echo "** 06-4_neutron_Create_initial_networks.sh"
./06-4_neutron_Create_initial_networks.sh >> $0.log

echo "** 07-1_horizon_Install_and_configure.sh ${controller}"
./07-1_horizon_Install_and_configure.sh ${controller} >> $0.log

echo "** 08-1_cinder_Install_and_configure_contoller_node.sh ${controller}"
./08-1_cinder_Install_and_configure_contoller_node.sh ${controller} >> $0.log

echo "** 08-2_cinder_Install_and_configure_storage_node.sh ${controller} ${compute1}"
./08-2_cinder_Install_and_configure_storage_node.sh ${controller} ${compute1} >> $0.log

echo "** 08-2_cinder_Install_and_configure_storage_node.sh ${controller} ${compute2}"
./08-2_cinder_Install_and_configure_storage_node.sh ${controller} ${compute2} >> $0.log
