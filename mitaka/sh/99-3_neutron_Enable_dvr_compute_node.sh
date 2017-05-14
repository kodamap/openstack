#!/bin/sh -e

export LANG=en_US.utf8

generate_dvr_sh () {

    cat << 'EOF' > ../lib/${SH}
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

# Configure the kernel to enable packet forwarding, enable iptables on bridges,
# and disable reverse path filtering. Edit the /etc/sysctl.conf file:
CONF=/etc/sysctl.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

if grep "net.bridge.bridge-nf-call-iptables=1" ${CONF} > /dev/null ; then
   cp -pf ${CONF}.org ${CONF}
fi

echo "net.ipv4.ip_forward=1" >> ${CONF}
echo "net.ipv4.conf.all.rp_filter=0" >> ${CONF}
echo "net.ipv4.conf.default.rp_filter=0" >> ${CONF}
echo "net.bridge.bridge-nf-call-iptables=1" >> ${CONF}
echo "net.bridge.bridge-nf-call-ip6tables=1" >> ${CONF}

# Load the new kernel configuration:
sysctl -p

# Configure common options. Edit the /etc/neutron/neutron.conf file:
CONF=/etc/neutron/neutron.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# Configure the Open vSwitch agent. Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file:
CONF=/etc/neutron/plugins/ml2/ml2_conf.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# Replace TUNNEL_INTERFACE_IP_ADDRESS with the IP address of the interface that handles GRE/VXLAN project networks.
openstack-config --set ${CONF} ovs local_ip ${INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS}
openstack-config --set ${CONF} ovs bridge_mappings external:br-ex
## openstack-config --set ${CONF} ovs bridge_mappings vlan:br-vlan,external:br-ex
openstack-config --set ${CONF} agent l2_population True
openstack-config --set ${CONF} agent tunnel_types gre,vxlan
openstack-config --set ${CONF} agent enable_distributed_routing True
openstack-config --set ${CONF} agent arp_responder True
openstack-config --set ${CONF} securitygroup enable_security_group True
openstack-config --set ${CONF} securitygroup enable_ipset True
openstack-config --set ${CONF} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

# Configure the L3 agent. Edit the /etc/neutron/l3_agent.ini file:
CONF=/etc/neutron/l3_agent.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# Note :
# The external_network_bridge option intentionally contains no value.
openstack-config --set ${CONF} DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set ${CONF} DEFAULT use_namespaces True
openstack-config --set ${CONF} DEFAULT external_network_bridge
openstack-config --set ${CONF} DEFAULT router_delete_namespaces True
openstack-config --set ${CONF} DEFAULT agent_mode dvr

# Configure the metadata agent. Edit the /etc/neutron/metadata_agent.ini file:
CONF=/etc/neutron/metadata_agent.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# Replace METADATA_SECRET with a suitable value for your environment.
openstack-config --set ${CONF} DEFAULT nova_metadata_ip ${controller}
openstack-config --set ${CONF} DEFAULT metadata_proxy_shared_secret ${METADATA_SECRET}


# Start the following services:
# - Open vSwitch
# - Open vSwitch agent
# - L3 agent
# - Metadata agent
echo
echo "** starting openvswitch.service..."
echo

systemctl enable openvswitch.service
systemctl stop openvswitch.service
systemctl start openvswitch.service
systemctl status openvswitch.service

echo
echo "** Starting the Open vSwitch (OVS) agent service..."
echo

systemctl enable neutron-openvswitch-agent.service
systemctl stop neutron-openvswitch-agent.service
systemctl start neutron-openvswitch-agent.service
systemctl status neutron-openvswitch-agent.service

# Add the external bridge:
ovs-vsctl add-br br-ex

# Add a port to the external bridge that connects to the physical external network interface:
# Replace INTERFACE_NAME with the actual interface name. For example, eth2 or ens256.
ovs-vsctl add-port br-ex ${INTERFACE_NAME}

# Note : Depending on your network interface driver, you may need to disable generic receive
# offload (GRO) to achieve suitable throughput between your instances and the external network.
# To temporarily disable GRO on the external network interface while testing your environment:
ethtool -K ${INTERFACE_NAME} gro off
ethtool -K ${INTERFACE_NAME} lro off

echo
echo "** Starting the Networking services..."
echo

systemctl enable neutron-l3-agent.service neutron-metadata-agent.service
systemctl stop neutron-l3-agent.service neutron-metadata-agent.service
systemctl start neutron-l3-agent.service neutron-metadata-agent.service
systemctl status neutron-l3-agent.service neutron-metadata-agent.service

echo
echo "** Disabling firewalld on `hostname`..."
echo

systemctl stop firewalld
systemctl disable firewalld

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main


if [ $# -ne 4 ]; then
    echo "** Usage: $0 <controller node ip> <compute node ip> <tunnel ip> <ext interface>"
    exit 1
fi

controller=$1
compute=$2
tunnel=$3
INTERFACE_NAME=$4

SH=enable_dvr_compute.sh
PW_FILE=OPENSTACK_PASSWD.ini

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
METADATA_SECRET=`get_passwd METADATA_SECRET`


ssh-copy-id root@${compute}
generate_dvr_sh
chmod 755 ../lib/${SH}
scp -p ${PW_FILE} root@${compute}:/root/
scp -p ../lib/${SH} root@${compute}:/root/
ssh root@${compute} "/root/${SH} ${controller} ${tunnel} ${INTERFACE_NAME} ${METADATA_SECRET}"

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
