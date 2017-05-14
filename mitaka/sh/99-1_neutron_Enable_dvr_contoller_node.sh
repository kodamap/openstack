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


# Scenario: High Availability using Distributed Virtual Routing (DVR)
# http://docs.openstack.org/kilo/networking-guide/scenario_dvr_ovs.html

enable_dvr_controller () {

    # Configure common options. Edit the /etc/neutron/neutron.conf file:
    CONF=/etc/neutron/neutron.conf
    echo
    echo "** Editing the ${CONF}..."
    echo

    test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

    # Note : Configuring the router_distributed = True option creates distributed routers
    # by default for all users.
    # Without it, only privileged users can create distributed routers using the --distributed True option
    # during router creation.

    openstack-config --set ${CONF} DEFAULT verbose True
    openstack-config --set ${CONF} DEFAULT router_distributed True
    openstack-config --set ${CONF} DEFAULT core_plugin ml2
    openstack-config --set ${CONF} DEFAULT service_plugins router
    openstack-config --set ${CONF} DEFAULT allow_overlapping_ips True

    # Configure the ML2 plug-in. Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file:
    CONF=/etc/neutron/plugins/ml2/ml2_conf.ini
    echo
    echo "** Editing the ${CONF}..."
    echo

    test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

    # Note :
    # The external value in the network_vlan_ranges option lacks VLAN ID ranges to support use of
    # arbitrary VLAN IDs by privileged users.
    openstack-config --set ${CONF} ml2 type_drivers flat,vlan,gre,vxlan
    #openstack-config --set ${CONF} ml2 tenant_network_types vlan,gre,vxlan
    openstack-config --set ${CONF} ml2 tenant_network_types gre,vxlan
    openstack-config --set ${CONF} ml2 mechanism_drivers openvswitch,l2population
    openstack-config --set ${CONF} ml2_type_flat flat_networks external
    #openstack-config --set ${CONF} ml2_type_vlan network_vlan_ranges external,vlan:1:1000
    openstack-config --set ${CONF} ml2_type_gre tunnel_id_ranges 1:1000
    #openstack-config --set ${CONF} ml2_type_vxlan vni_ranges 1:1000
    #openstack-config --set ${CONF} ml2_type_vxlan vxlan_group 239.1.1.1
    openstack-config --set ${CONF} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
    openstack-config --set ${CONF} securitygroup enable_security_group True
    openstack-config --set ${CONF} securitygroup enable_ipset True

}


# main

enable_dvr_controller

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
systemctl stop neutron-server.service
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
echo "** neutron agent-list"
echo

neutron agent-list

echo
echo "Done."
