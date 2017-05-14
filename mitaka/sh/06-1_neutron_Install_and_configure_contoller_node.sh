#!/bin/sh -e

export LANG=en_US.utf8

if [[ $# -ne 3 ]]; then
    echo "** Usage: $0 <controller IP> <OVERLAY_INTERFACE_IP_ADDRESS> <PROVIDER_INTERFACE_NAME>"
    exit 1
fi

controller=$1
OVERLAY_INTERFACE_IP_ADDRESS=$2
PROVIDER_INTERFACE_NAME=$3

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
NEUTRON_PASS=`get_passwd NEUTRON_PASS`
NEUTRON_DBPASS=`get_passwd NEUTRON_DBPASS`
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`
METADATA_SECRET=`get_passwd METADATA_SECRET`

prerequisites () {

  sed -i "s/NEUTRON_DBPASS/${NEUTRON_DBPASS}/g" ../sql/neutron.sql

  # Create the neutron database and Grant proper access to the neutron database:
  echo
  echo "** Creating neutron database and neutron user..."
  echo

  mysql -u root -p${DATABASE_PASS} < ../sql/neutron.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create the neutron user:
  echo
  echo "** Creating the neutron user..."
  echo

  openstack user create --domain default --password ${NEUTRON_PASS} neutron

  # Add the admin role to the neutron user:
  echo
  echo "** Adding the admin role to the neutron user and service project..."
  echo

  openstack role add --project service --user neutron admin

  # Create the neutron service entity:
  echo
  echo "** Creating the neutron service entity..."
  echo

  openstack service create --name neutron \
    --description "OpenStack Networking" network

  # Create the Networking service API endpoint:
  echo
  echo "** Creating the Networking service API endpoint..."
  echo

  openstack endpoint create --region RegionOne \
    network public http://${controller}:9696

  openstack endpoint create --region RegionOne \
    network internal http://${controller}:9696

  openstack endpoint create --region RegionOne \
    network admin http://${controller}:9696

  echo
  echo "** openstack service list"
  echo

  openstack service list

}

install_components () {

  # To install the Networking components
  # Install the packages
  echo
  echo "** Installing the packages..."
  echo

  yum -y install openstack-neutron openstack-neutron-ml2 \
    openstack-neutron-linuxbridge ebtables ipset

}

configure_server_component () {

  # Edit the /etc/neutron/neutron.conf file and complete the following actions:
  CONF=/etc/neutron/neutron.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://neutron:${NEUTRON_DBPASS}@${controller}/neutron

  # In the [DEFAULT] section, enable the Modular Layer 2 (ML2) plug-in, router service, and overlapping IP addresses:
  openstack-config --set ${CONF} DEFAULT core_plugin ml2
  openstack-config --set ${CONF} DEFAULT service_plugins router
  openstack-config --set ${CONF} DEFAULT allow_overlapping_ips True

  # In the [DEFAULT] and [oslo_messaging_rabbit] sections, configure RabbitMQ message queue access:
  openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_host ${controller}
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_userid openstack
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_password ${RABBIT_PASS}

  # In the [DEFAULT] and [keystone_authtoken] sections, configure Identity service access:
  # Note : Comment out or remove any other options in the [keystone_authtoken] section.
  openstack-config --set ${CONF} DEFAULT auth_strategy keystone
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username neutron
  openstack-config --set ${CONF} keystone_authtoken password ${NEUTRON_PASS}

  sed -i '/^auth_uri = http:\/\/127.0.0.1:35357\/v2.0\//s/^/#/' ${CONF}
  sed -i '/^identity_uri = http:\/\/127.0.0.1:5000/s/^/#/' ${CONF}
  sed -i '/^admin_tenant_name = %SERVICE_TENANT_NAME%/s/^/#/' ${CONF}
  sed -i '/^admin_user = %SERVICE_USER%/s/^/#/' ${CONF}
  sed -i '/^admin_password = %SERVICE_PASSWORD%/s/^/#/' ${CONF}

  # In the [DEFAULT] and [nova] sections, configure Networking to notify Compute of network
  # topology changes:
  openstack-config --set ${CONF} DEFAULT notify_nova_on_port_status_changes True
  openstack-config --set ${CONF} DEFAULT notify_nova_on_port_data_changes True

  openstack-config --set ${CONF} nova auth_url http://${controller}:35357
  openstack-config --set ${CONF} nova auth_type password
  openstack-config --set ${CONF} nova project_domain_name default
  openstack-config --set ${CONF} nova user_domain_name default
  openstack-config --set ${CONF} nova region_name RegionOne
  openstack-config --set ${CONF} nova project_name service
  openstack-config --set ${CONF} nova username nova
  openstack-config --set ${CONF} nova password ${NOVA_PASS}

  openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/neutron/tmp

  # (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
  ### openstack-config --set ${CONF} DEFAULT verbose  True

}

configure_ml2_plugin () {

  # The ML2 plug-in uses the Linux bridge mechanism to build layer-2 (bridging and switching)
  # virtual networking infrastructure for instances.
  # Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file and complete the following actions:
  CONF=/etc/neutron/plugins/ml2/ml2_conf.ini
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [ml2] section, enable flat, VLAN, and VXLAN networks:
  openstack-config --set ${CONF} ml2 type_drivers flat,vlan,vxlan

  # In the [ml2] section, enable VXLAN self-service networks:
  openstack-config --set ${CONF} ml2 tenant_network_types vxlan

  # In the [ml2] section, enable the Linux bridge and layer-2 population mechanisms:
  # NOTE:
  # The Linux bridge agent only supports VXLAN overlay networks.
  openstack-config --set ${CONF} ml2 mechanism_drivers linuxbridge,l2population

  # In the [ml2] section, enable the port security extension driver:
  openstack-config --set ${CONF} ml2 extension_drivers port_security

  # In the [ml2_type_flat] section, configure the provider virtual network as a flat network:
  openstack-config --set ${CONF} ml2_type_flat flat_networks provider

  # In the [ml2_type_vxlan] section, configure the VXLAN network identifier range for self-service networks:
  openstack-config --set ${CONF} ml2_type_vxlan vni_ranges 1:1000

  # In the [securitygroup] section, enable ipset to increase efficiency of security group rules:
  openstack-config --set ${CONF} securitygroup enable_ipset True

}

configure_linux_bridge_agent () {

  # The Linux bridge agent builds layer-2 (bridging and switching) virtual networking infrastructure
  # for instances and handles security groups.
  # Edit the /etc/neutron/plugins/ml2/linuxbridge_agent.ini file and complete the following actions:

  # To configure Compute to use Networking
  # Edit the /etc/neutron/plugins/ml2/linuxbridge_agent.ini file and complete the following actions:
  CONF=/etc/neutron/plugins/ml2/linuxbridge_agent.ini
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [linux_bridge] section, map the provider virtual network to the provider physical network interface:
  openstack-config --set ${CONF} linux_bridge physical_interface_mappings provider:${PROVIDER_INTERFACE_NAME}

  # In the [vxlan] section, enable VXLAN overlay networks, configure the IP address of the physical network
  # interface that handles overlay networks, and enable layer-2 population:
  openstack-config --set ${CONF} vxlan enable_vxlan True
  openstack-config --set ${CONF} vxlan local_ip ${OVERLAY_INTERFACE_IP_ADDRESS}
  openstack-config --set ${CONF} vxlan l2_population True

  # In the [securitygroup] section, enable security groups and configure the Linux bridge iptables firewall driver:
  openstack-config --set ${CONF} securitygroup enable_security_group True
  openstack-config --set ${CONF} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

}

configure_l3_agent () {

  # The Layer-3 (L3) agent provides routing and NAT services for self-service virtual networks.
  # Edit the /etc/neutron/l3_agent.ini file and complete the following actions:
  CONF=/etc/neutron/l3_agent.ini
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [DEFAULT] section, configure the Linux bridge interface driver and external network bridge:
  # NOTE:
  # The external_network_bridge option intentionally lacks a value to enable multiple external networks on a single agent.
  openstack-config --set ${CONF} DEFAULT interface_driver neutron.agent.linux.interface.BridgeInterfaceDriver
  openstack-config --set ${CONF} DEFAULT external_network_bridge

}

configure_dhcp_agent () {

  # The DHCP agent provides DHCP services for virtual networks.
  # Edit the /etc/neutron/dhcp_agent.ini file and complete the following actions:
  CONF=/etc/neutron/dhcp_agent.ini
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  openstack-config --set ${CONF} DEFAULT interface_driver neutron.agent.linux.interface.BridgeInterfaceDriver
  openstack-config --set ${CONF} DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
  openstack-config --set ${CONF} DEFAULT enable_isolated_metadata True

}

configure_metadata_agent () {

  # The metadata agent provides configuration information such as credentials to instances.
  # Edit the /etc/neutron/metadata_agent.ini file and complete the following actions:
  CONF=/etc/neutron/metadata_agent.ini
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  openstack-config --set ${CONF} DEFAULT nova_metadata_ip ${controller}
  openstack-config --set ${CONF} DEFAULT metadata_proxy_shared_secret ${METADATA_SECRET}

}

configure_compute_with_networking () {

  # To configure Compute to use Networking
  # Edit the /etc/nova/nova.conf file on the controller node and complete the following actions:
  CONF=/etc/nova/nova.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [neutron] section, configure access parameters:
  openstack-config --set ${CONF} neutron url http://${controller}:9696
  openstack-config --set ${CONF} neutron auth_url http://${controller}:35357
  openstack-config --set ${CONF} neutron auth_type password
  openstack-config --set ${CONF} neutron project_domain_name default
  openstack-config --set ${CONF} neutron user_domain_name default
  openstack-config --set ${CONF} neutron region_name RegionOne
  openstack-config --set ${CONF} neutron project_name service
  openstack-config --set ${CONF} neutron username neutron
  openstack-config --set ${CONF} neutron password ${NEUTRON_PASS}

  openstack-config --set ${CONF} neutron service_metadata_proxy True
  openstack-config --set ${CONF} neutron metadata_proxy_shared_secret ${METADATA_SECRET}

}

finalize_installation () {

  # To finalize installation
  #
  # The Networking service initialization scripts expect a symbolic link
  # /etc/neutron/plugin.ini pointing to the ML2 plug-in configuration file,
  # /etc/neutron/plugins/ml2/ml2_conf.ini.
  # If this symbolic link does not exist, create it using the following command:
  ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

  # Populate the databasae
  # NOTE:
  # Database population occurs later for Networking because the script requires complete server
  # and plug-in configuration files.
  echo
  echo "** neutron-db-manage..."
  echo
  su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
    --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

  # Restart the Compute API services:
  echo
  echo "** Restarting compute api..."
  echo

  systemctl restart openstack-nova-api.service

  # Start the Networking services and configure them to start when the system boots.
  # For both networking options:
  echo
  echo "** starting neutron service..."
  echo

  systemctl enable neutron-server.service \
   neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
   neutron-metadata-agent.service

  systemctl start neutron-server.service \
   neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
   neutron-metadata-agent.service

  systemctl status neutron-server.service \
    neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
    neutron-metadata-agent.service

  # For networking option 2, also enable and start the layer-3 service:
  echo
  echo "** starting layer-3 agent service..."
  echo

  systemctl enable neutron-l3-agent.service
  systemctl start neutron-l3-agent.service
  systemctl status neutron-l3-agent.service

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # List loaded extensions to verify successful launch of the neutron-server process:
  echo
  echo "** neutron ext-list"
  echo

  neutron ext-list


}


#main
prerequisites
install_components
configure_server_component
configure_ml2_plugin
configure_linux_bridge_agent
configure_l3_agent
configure_dhcp_agent
configure_metadata_agent
configure_compute_with_networking
finalize_installation

echo
echo "Done."
