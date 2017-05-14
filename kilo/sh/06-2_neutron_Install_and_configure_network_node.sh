#!/bin/sh -e

export LANG=en_US.utf8

function generate_network_sh {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

if [ $# -ne 4 ]; then
   echo "** Usage: $0 <controller ip> <compute tunnel ip> <external interface name> <metadata secret>"
   exit 1
fi

controller=$1
INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS=$2
INTERFACE_NAME=$3
METADATA_SECRET=$4

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
NEUTRON_PASS=`get_passwd NEUTRON_PASS`
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`


# To configure prerequisites
# Edit the /etc/sysctl.conf file to contain the following parameters:
CONF=/etc/sysctl.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

if grep "net.ipv4.ip_forward=1" ${CONF} > /dev/null ; then
   cp -pf ${CONF}.org ${CONF}
fi

echo "net.ipv4.ip_forward=1" >> ${CONF}
echo "net.ipv4.conf.all.rp_filter=0" >> ${CONF}
echo "net.ipv4.conf.default.rp_filter=0" >> ${CONF}

# Implement the changes
sysctl -p

# To install the Networking components
echo
echo "** Installing the packages..."
echo

yum -y -q install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch

# To configure the Networking common components
# 
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

# In the [ml2_type_flat] section, configure the external flat provider network
openstack-config --set ${CONF} ml2_type_flat flat_networks external

# In the [ml2_type_gre] section, configure the tunnel identifier (id) range:
openstack-config --set ${CONF} ml2_type_gre tunnel_id_ranges 1:1000

# In the [securitygroup] section, enable security groups, enable ipset,
# and configure the OVS iptables firewall driver:
openstack-config --set ${CONF} securitygroup enable_security_group True
openstack-config --set ${CONF} securitygroup enable_ipset True
openstack-config --set ${CONF} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

# In the [ovs] section, enable tunnels, configure the local tunnel endpoint,
# and map the external flat provider network to the br-ex external network bridge:
openstack-config --set ${CONF} ovs local_ip ${INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS}
openstack-config --set ${CONF} ovs bridge_mappings external:br-ex

# In the [agent] section, enable GRE tunnels:
openstack-config --set ${CONF} agent tunnel_types gre

# To configure the Layer-3 (L3) agent
#
# Edit the /etc/neutron/l3_agent.ini file and complete the following actions:
# In the [DEFAULT] section, configure the interface driver,
# external network bridge, and enable deletion of defunct router namespaces:
#
# Note : The external_network_bridge option intentionally lacks a value to enable multiple
# external networks on a single agent.
CONF=/etc/neutron/l3_agent.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set ${CONF} DEFAULT external_network_bridge 
openstack-config --set ${CONF} DEFAULT router_delete_namespaces True

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# To configure the DHCP agent
#
# Edit the /etc/neutron/dhcp_agent.ini file and complete the following actions:
# In the [DEFAULT] section, configure the interface and DHCP drivers and enable deletion of
# defunct DHCP namespaces:
CONF=/etc/neutron/dhcp_agent.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set ${CONF} DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
openstack-config --set ${CONF} DEFAULT dhcp_delete_namespaces True

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True


# (Optional
#
# Tunneling protocols such as GRE include additional packet headers that increase overhead and
# decrease space available for the payload or user data.
# Without knowledge of the virtual network infrastructure, instances attempt to send packets
# using the default Ethernet maximum transmission unit (MTU) of 1500 bytes.
# Internet protocol (IP) networks contain the path MTU discovery (PMTUD) mechanism to detect
# end-to-end MTU and adjust packet size accordingly.
# However, some operating systems and networks block or otherwise lack support for PMTUD
# causing performance degradation or connectivity failure.
#
# Ideally, you can prevent these problems by enabling jumbo frames on the physical network
# that contains your tenant virtual networks.
# Jumbo frames support MTUs up to approximately 9000 bytes which negates the impact of GRE
# overhead on virtual networks.
# However, many network devices lack support for jumbo frames and OpenStack administrators
# often lack control over network infrastructure. Given the latter complications,
# you can also prevent MTU problems by reducing the instance MTU to account for GRE overhead.
# Determining the proper MTU value often takes experimentation, but 1454 bytes works in most
# environments.
# You can configure the DHCP server that assigns IP addresses to your instances to also adjust the MTU.
#
# Note : Some cloud images ignore the DHCP MTU option in which case you should configure it
# using metadata, a script, or another suitable method.
#
#
# Edit the /etc/neutron/dhcp_agent.ini file and complete the following action:
# In the [DEFAULT] section, enable the dnsmasq configuration file:

openstack-config --set ${CONF} DEFAULT dnsmasq_config_file /etc/neutron/dnsmasq-neutron.conf

# Create and edit the /etc/neutron/dnsmasq-neutron.conf file and complete the following action:
# Enable the DHCP MTU option (26) and configure it to 1454 bytes:

echo "dhcp-option-force=26,1454" > /etc/neutron/dnsmasq-neutron.conf

# Kill any existing dnsmasq processes:
if ps -ef |grep dnsmasq |grep -v grep ; then pkill dnsmasq ; fi


# To configure the metadata agent
#
# Edit the /etc/neutron/metadata_agent.ini file and complete the following actions:
# In the [DEFAULT] section, configure access parameters:
CONF=/etc/neutron/metadata_agent.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} DEFAULT auth_uri http://${controller}:5000
openstack-config --set ${CONF} DEFAULT auth_url http://${controller}:35357
openstack-config --set ${CONF} DEFAULT auth_region RegionOne
openstack-config --set ${CONF} DEFAULT auth_plugin password
openstack-config --set ${CONF} DEFAULT project_domain_id default
openstack-config --set ${CONF} DEFAULT user_domain_id default
openstack-config --set ${CONF} DEFAULT project_name service
openstack-config --set ${CONF} DEFAULT username neutron
openstack-config --set ${CONF} DEFAULT password ${NEUTRON_PASS}

# In the [DEFAULT] section, configure the metadata host:
openstack-config --set ${CONF} DEFAULT nova_metadata_ip ${controller}

# In the [DEFAULT] section, configure the metadata proxy shared secret:
openstack-config --set ${CONF} DEFAULT metadata_proxy_shared_secret ${METADATA_SECRET}

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True


# To configure the Open vSwitch (OVS) service
#
# The OVS service provides the underlying virtual networking framework for instances.
# The integration bridge br-int handles internal instance network traffic within OVS.
# The external bridge br-ex handles external instance network traffic within OVS.
# The external bridge requires a port on the physical external network interface to
# provide instances with external network access. In essence, this port connects
# the virtual and physical external networks in your environment.
#
# Start the OVS service and configure it to start when the system boots:
echo
echo "** starting openvswitch.service..."
echo

systemctl enable openvswitch.service
systemctl start openvswitch.service
systemctl status openvswitch.service

# Add the external bridge:
ovs-vsctl add-br br-ex

# Add a port to the external bridge that connects to the physical external network interface:
# Replace INTERFACE_NAME with the actual interface name. For example, eth2 or ens256.
ovs-vsctl add-port br-ex ${INTERFACE_NAME}

# Note : Depending on your network interface driver, you may need to disable generic receive
# offload (GRO) to achieve suitable throughput between your instances and the external network.
# To temporarily disable GRO on the external network interface while testing your environment:
ethtool -K ${INTERFACE_NAME} gro off

# To finalize the installation
# The Networking service initialization scripts expect a symbolic link /etc/neutron/plugin.ini
# pointing to the ML2 plug-in configuration file, /etc/neutron/plugins/ml2/ml2_conf.ini.
# If this symbolic link does not exist, create it using the following command:

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

# Due to a packaging bug, the Open vSwitch agent initialization script explicitly looks for
# the Open vSwitch plug-in configuration file rather than a symbolic link /etc/neutron/plugin.ini
# pointing to the ML2 plug-in configuration file.
# Run the following commands to resolve this issue:
cp /usr/lib/systemd/system/neutron-openvswitch-agent.service \
  /usr/lib/systemd/system/neutron-openvswitch-agent.service.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' \
  /usr/lib/systemd/system/neutron-openvswitch-agent.service

# Start the Networking services and configure them to start when the system boots:
echo
echo "** Starting the Networking services..."
echo

systemctl enable neutron-openvswitch-agent.service neutron-l3-agent.service \
  neutron-dhcp-agent.service neutron-metadata-agent.service \
  neutron-ovs-cleanup.service
systemctl start neutron-openvswitch-agent.service neutron-l3-agent.service \
  neutron-dhcp-agent.service neutron-metadata-agent.service
systemctl status neutron-openvswitch-agent.service neutron-l3-agent.service \
  neutron-dhcp-agent.service neutron-metadata-agent.service

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main

if [ $# -ne 4 ]; then
    echo "** Usage: $0 <controller node ip> <network node ip> <tunnel ip> <ext interface>"
    exit 1
fi

controller=$1
network=$2
tunnel=$3
INTERFACE_NAME=$4

SH=install_and_configure_network.sh
PW_FILE=OPENSTACK_PASSWD.ini

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
METADATA_SECRET=`get_passwd METADATA_SECRET`

ssh-copy-id root@${network}
generate_network_sh
chmod 755 ../lib//${SH}
scp -p ${PW_FILE} root@${network}:/root/
scp -p ../lib//${SH} root@${network}:/root/
ssh root@${network} "/root/${SH} ${controller} ${tunnel} ${INTERFACE_NAME} ${METADATA_SECRET}"


# On the controller node, edit the /etc/nova/nova.conf file and complete the following action:
# In the [neutron] section, enable the metadata proxy and configure the secret:
CONF=/etc/nova/nova.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} neutron service_metadata_proxy True
openstack-config --set ${CONF} neutron metadata_proxy_shared_secret ${METADATA_SECRET}

# On the controller node, restart the Compute API service:
echo
echo "** Restarting the Compute API service"
echo 
systemctl restart openstack-nova-api.service
systemctl status openstack-nova-api.service

# Verify operation
# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# List agents to verify successful launch of the neutron agents:
echo
echo "** neutron agent-list"
echo

sleep 3;

neutron agent-list

echo
echo "** Done."
