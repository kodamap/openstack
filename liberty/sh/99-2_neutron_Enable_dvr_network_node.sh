#!/bin/sh -e

export LANG=en_US.utf8

generate_dvr_sh () {

    cat << 'EOF' > ../lib/${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

if [ $# -ne 3 ]; then
   echo "** Usage: $0 <controller ip> <compute tunnel ip> <metadata secret>"
   exit 1
fi

controller=$1
INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS=$2
METADATA_SECRET=$3


# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
NEUTRON_PASS=`get_passwd NEUTRON_PASS`
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# Scenario: High Availability using Distributed Virtual Routing (DVR)
# http://docs.openstack.org/kilo/networking-guide/scenario_dvr_ovs.html

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

# To configure the Networking common components
#
# Edit the /etc/neutron/neutron.conf file and complete the following actions:
CONF=/etc/neutron/neutron.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# To configure the Modular Layer 2 (ML2) plug-in
# Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file and complete the following actions:
CONF=/etc/neutron/plugins/ml2/ml2_conf.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# Configure the Open vSwitch agent. Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file
# Replace TUNNEL_INTERFACE_IP_ADDRESS with the IP address of the interface that handles GRE/VXLAN project networks.
openstack-config --set ${CONF} ovs local_ip ${INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS}
openstack-config --set ${CONF} ovs bridge_mappings external:br-ex
##openstack-config --set ${CONF} ovs bridge_mappings vlan:br-vlan,external:br-ex

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
openstack-config --set ${CONF} DEFAULT external_network_bridge
openstack-config --set ${CONF} DEFAULT router_delete_namespaces True
openstack-config --set ${CONF} DEFAULT use_namespaces True
openstack-config --set ${CONF} DEFAULT agent_mode dvr_snat

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# Configure the DHCP agent. Edit the /etc/neutron/dhcp_agent.ini file:
CONF=/etc/neutron/dhcp_agent.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set ${CONF} DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
openstack-config --set ${CONF} DEFAULT dhcp_delete_namespaces True
openstack-config --set ${CONF} DEFAULT use_namespaces True

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# (Optional) Reduce MTU for GRE/VXLAN project networks.

openstack-config --set ${CONF} DEFAULT dnsmasq_config_file /etc/neutron/dnsmasq-neutron.conf

echo "dhcp-option-force=26,1450" > /etc/neutron/dnsmasq-neutron.conf

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

openstack-config --set ${CONF} DEFAULT nova_metadata_ip ${controller}
openstack-config --set ${CONF} DEFAULT metadata_proxy_shared_secret ${METADATA_SECRET}

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# Start the following services:
# - Open vSwitch
# - Open vSwitch agent
# - L3 agent
# - DHCP agent
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


echo
echo "** Starting the Networking services..."
echo

systemctl enable neutron-openvswitch-agent.service neutron-l3-agent.service \
  neutron-dhcp-agent.service neutron-metadata-agent.service \
  neutron-ovs-cleanup.service
systemctl stop neutron-openvswitch-agent.service neutron-l3-agent.service \
  neutron-dhcp-agent.service neutron-metadata-agent.service
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

if [ $# -ne 3 ]; then
    echo "** Usage: $0 <controller node ip> <network node ip> <tunnel ip>"
    exit 1
fi

controller=$1
network=$2
tunnel=$3

SH=enable_dvr_network.sh
PW_FILE=OPENSTACK_PASSWD.ini

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
METADATA_SECRET=`get_passwd METADATA_SECRET`

ssh-copy-id root@${network}
generate_dvr_sh
chmod 755 ../lib/${SH}
scp -p ${PW_FILE} root@${network}:/root/
scp -p ../lib/${SH} root@${network}:/root/
ssh root@${network} "/root/${SH} ${controller} ${tunnel} ${METADATA_SECRET}"

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
