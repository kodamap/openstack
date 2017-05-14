#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
NEUTRON_PASS=`get_passwd NEUTRON_PASS`
NEUTRON_DBPASS=`get_passwd NEUTRON_DBPASS`
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

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

openstack user create --password ${NEUTRON_PASS} neutron

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

openstack endpoint create \
  --publicurl http://${controller}:9696 \
  --adminurl http://${controller}:9696 \
  --internalurl http://${controller}:9696 \
  --region RegionOne \
  network

echo
echo "** openstack service list"
echo

openstack service list

# To install the Networking components
# Install the packages
echo
echo "** Installing the packages..."
echo

yum -y -q install openstack-neutron openstack-neutron-ml2 python-neutronclient which

# Edit the /etc/neutron/neutron.conf file and complete the following actions:
CONF=/etc/neutron/neutron.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [database] section, configure database access:
openstack-config --set ${CONF} database connection mysql://neutron:${NEUTRON_DBPASS}@${controller}/neutron

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
openstack-config --set ${CONF} keystone_authtoken auth_plugin password
openstack-config --set ${CONF} keystone_authtoken project_domain_id default
openstack-config --set ${CONF} keystone_authtoken user_domain_id default
openstack-config --set ${CONF} keystone_authtoken project_name service
openstack-config --set ${CONF} keystone_authtoken username neutron
openstack-config --set ${CONF} keystone_authtoken password ${NEUTRON_PASS}

sed -i '/^auth_uri = http:\/\/127.0.0.1:35357\/v2.0\//s/^/#/' ${CONF}
sed -i '/^identity_uri = http:\/\/127.0.0.1:5000/s/^/#/' ${CONF}
sed -i '/^admin_tenant_name = %SERVICE_TENANT_NAME%/s/^/#/' ${CONF}
sed -i '/^admin_user = %SERVICE_USER%/s/^/#/' ${CONF}
sed -i '/^admin_password = %SERVICE_PASSWORD%/s/^/#/' ${CONF}

# In the [DEFAULT] section, enable the Modular Layer 2 (ML2) plug-in,
# router service, and overlapping IP addresses:
openstack-config --set ${CONF} DEFAULT core_plugin ml2
openstack-config --set ${CONF} DEFAULT service_plugins router
openstack-config --set ${CONF} DEFAULT allow_overlapping_ips True

# In the [DEFAULT] and [nova] sections, configure Networking to notify Compute of network
# topology changes:
openstack-config --set ${CONF} DEFAULT notify_nova_on_port_status_changes True
openstack-config --set ${CONF} DEFAULT notify_nova_on_port_data_changes True
openstack-config --set ${CONF} DEFAULT nova_url http://${controller}:8774/v2

openstack-config --set ${CONF} nova auth_url http://${controller}:35357
openstack-config --set ${CONF} nova auth_plugin password
openstack-config --set ${CONF} nova project_domain_id default
openstack-config --set ${CONF} nova user_domain_id default
openstack-config --set ${CONF} nova region_name RegionOne
openstack-config --set ${CONF} nova project_name service
openstack-config --set ${CONF} nova username nova
openstack-config --set ${CONF} nova password ${NOVA_PASS}

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# To configure the Modular Layer 2 (ML2) plug-in
# Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file and complete the following actions:
CONF=/etc/neutron/plugins/ml2/ml2_conf.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [ml2] section, enable the flat, VLAN, generic routing encapsulation (GRE),
# and virtual extensible LAN (VXLAN) network type drivers, GRE tenant networks,
# and the OVS mechanism driver:
#
# Warning : Once you configure the ML2 plug-in, changing values in the type_drivers
# option can lead to database inconsistency.
#
# Example: tenant_network_types = vlan,gre,vxlan
openstack-config --set ${CONF} ml2 type_drivers flat,vlan,gre,vxlan
openstack-config --set ${CONF} ml2 tenant_network_types gre
openstack-config --set ${CONF} ml2 mechanism_drivers openvswitch

# In the [ml2_type_gre] section, configure the tunnel identifier (id) range:
openstack-config --set ${CONF} ml2_type_gre tunnel_id_ranges 1:1000

# In the [securitygroup] section, enable security groups, enable ipset,
# and configure the OVS iptables firewall driver:
openstack-config --set ${CONF} securitygroup enable_security_group True
openstack-config --set ${CONF} securitygroup enable_ipset True
openstack-config --set ${CONF} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

# To configure Compute to use Networking
# Edit the /etc/nova/nova.conf file on the controller node and complete the following actions:
CONF=/etc/nova/nova.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org


# In the [DEFAULT] section, configure the APIs and drivers:
#
# Note: By default, Compute uses an internal firewall service. 
# Since Networking includes a firewall service, you must disable the Compute firewall service
# by using the nova.virt.firewall.NoopFirewallDriver firewall driver.
openstack-config --set ${CONF} DEFAULT network_api_class nova.network.neutronv2.api.API
openstack-config --set ${CONF} DEFAULT security_group_api neutron
openstack-config --set ${CONF} DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
openstack-config --set ${CONF} DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

# In the [neutron] section, configure access parameters:
openstack-config --set ${CONF} neutron url http://${controller}:9696
openstack-config --set ${CONF} neutron auth_strategy keystone
openstack-config --set ${CONF} neutron admin_auth_url http://${controller}:35357/v2.0
openstack-config --set ${CONF} neutron admin_tenant_name service
openstack-config --set ${CONF} neutron admin_username neutron
openstack-config --set ${CONF} neutron admin_password ${NEUTRON_PASS}

# To finalize installation
#
# The Networking service initialization scripts expect a symbolic link
# /etc/neutron/plugin.ini pointing to the ML2 plug-in configuration file,
# /etc/neutron/plugins/ml2/ml2_conf.ini.
# If this symbolic link does not exist, create it using the following command:
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

# Populate the databasae
echo
echo "** neutron-db-manage..."
echo
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

# Restart the Compute services:
echo
echo "** Restarting nova compute..."
echo

systemctl restart openstack-nova-api.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service

systemctl status openstack-nova-api.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service

# Start the Networking service and configure it to start when the system boots:
echo
echo "** starting neutron service..."
echo

systemctl enable neutron-server.service
systemctl start neutron-server.service
systemctl status neutron-server.service


# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# List loaded extensions to verify successful launch of the neutron-server process:
echo
echo "** neutron ext-list"
echo

neutron ext-list

echo
echo "Done."