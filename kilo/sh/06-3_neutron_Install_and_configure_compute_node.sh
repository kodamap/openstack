#!/bin/sh -e

export LANG=en_US.utf8

SH=install_and_configure_neutron.sh
PW_FILE=OPENSTACK_PASSWD.ini

function generate_neutron_sh {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

if [ $# -ne 2 ]; then
    echo "** Usage: $0 <controller node ip> <compute tunnel ip>"
    exit 1
fi

controller=$1
INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS=$2

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
NEUTRON_PASS=`get_passwd NEUTRON_PASS`
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# Enabling firewall
echo
echo "** Enabling firewalld on `hostname`..."
echo

systemctl enable firewalld
systemctl start firewalld


# To configure prerequisites
# Edit the /etc/sysctl.conf file to contain the following parameters:
CONF=/etc/sysctl.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

if grep "net.bridge.bridge-nf-call-iptables=1" ${CONF} > /dev/null ; then
   cp -pf ${CONF}.org ${CONF}
fi

echo "net.ipv4.conf.all.rp_filter=0" >> ${CONF}
echo "net.ipv4.conf.default.rp_filter=0" >> ${CONF}
echo "net.bridge.bridge-nf-call-iptables=1" >> ${CONF}
echo "net.bridge.bridge-nf-call-ip6tables=1" >> ${CONF}

# Implement the changes
sysctl -p

# To install the Networking components
echo
echo "** Installing the packages..."
echo

yum -y -q install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch


# To configure the Networking common components
#
# The Networking common component configuration includes the authentication mechanism,
# message queue, and plug-in.
#
# Edit the /etc/neutron/neutron.conf file and complete the following actions:
CONF=/etc/neutron/neutron.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [database] section, comment out any connection options because compute nodes
# do not directly access the database.

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

# In the [ovs] section, enable tunnels, configure the local tunnel endpoint,
openstack-config --set ${CONF} ovs local_ip ${INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS}

# In the [agent] section, enable GRE tunnels:
openstack-config --set ${CONF} agent tunnel_types gre

# To configure the Open vSwitch (OVS) service
#
# The OVS service provides the underlying virtual networking framework for instances.
#Start the OVS service and configure it to start when the system boots:echo
echo
echo "** starting openvswitch.service..."
echo

systemctl enable openvswitch.service
systemctl start openvswitch.service
systemctl status openvswitch.service

# To configure Compute to use Networking
# By default, distribution packages configure Compute to use legacy networking.
# You must reconfigure Compute to manage networks through Networking.
# Edit the /etc/nova/nova.conf file and complete the following actions:
CONF=/etc/nova/nova.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [DEFAULT] section, configure the APIs and drivers:
#
# Note : By default, Compute uses an internal firewall service.
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


# Disabling firewall
echo
echo "** Disabling firewalld on `hostname`..."
echo

systemctl stop firewalld
systemctl disable firewalld


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

# Restart the Compute service:
echo
echo "** Restarting nova compute service"
echo

systemctl restart openstack-nova-compute.service
systemctl status openstack-nova-compute.service

# Start the Open vSwitch (OVS) agent and configure it to start when the system boots:
echo
echo "** Starting the Open vSwitch (OVS) agent service..."
echo

systemctl enable neutron-openvswitch-agent.service
systemctl start neutron-openvswitch-agent.service
systemctl status neutron-openvswitch-agent.service


echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main


if [ $# -ne 3 ]; then
    echo "** Usage: $0 <controller node ip> <compute node ip> <tunnel ip>"
    exit 1
fi

controller=$1
compute=$2
tunnel=$3

ssh-copy-id root@${compute}
generate_neutron_sh
chmod 755 ../lib//${SH}
scp -p ${PW_FILE} root@${compute}:/root/
scp -p ../lib//${SH} root@${compute}:/root/
ssh root@${compute} "/root/${SH} ${controller} ${tunnel}"

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
echo "Done."