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

if [ $# -ne 3 ]; then
    echo "** Usage: $0 <controller ip> <OVERLAY_INTERFACE_IP_ADDRESS> <PROVIDER_INTERFACE_NAME>"
    exit 1
fi

controller=$1
OVERLAY_INTERFACE_IP_ADDRESS=$2
PROVIDER_INTERFACE_NAME=$3

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
NEUTRON_PASS=`get_passwd NEUTRON_PASS`
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# To install the Networking components
echo
echo "** Installing the packages..."
echo

yum -y install openstack-neutron-linuxbridge ebtables

# nova.virt.driver [-] Unable to load the virtualization driver
# https://ask.openstack.org/en/question/82191/novavirtdriver-unable-to-load-the-virtualization-driver/

yum -y install ipset

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

# In the [oslo_concurrency] section, configure the lock path:
openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/neutron/tmp

# The Linux bridge agent builds layer-2 (bridging and switching) virtual networking infrastructure
# for instances and handles security groups.
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


# To finalize the installation

# Restart the Compute service:
echo
echo "** Restarting nova compute service"
echo

systemctl restart openstack-nova-compute.service
systemctl status openstack-nova-compute.service

# Start the Linux bridge agent and configure it to start when the system boots:
echo
echo "** Starting neutron linux_bridge agent service"
echo

systemctl enable neutron-linuxbridge-agent.service
systemctl start neutron-linuxbridge-agent.service
systemctl status neutron-linuxbridge-agent.service

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main


if [ $# -ne 4 ]; then
    echo "** Usage: $0 <controller node ip> <compute ip> <OVERLAY_INTERFACE_IP_ADDRESS> <PROVIDER_INTERFACE_NAME>"
    exit 1
fi

controller=$1
compute=$2
OVERLAY_INTERFACE_IP_ADDRESS=$3
PROVIDER_INTERFACE_NAME=$4

ssh-copy-id root@${compute}
generate_neutron_sh
chmod 755 ../lib//${SH}
scp -p ${PW_FILE} root@${compute}:/root/
scp -p ../lib//${SH} root@${compute}:/root/
ssh root@${compute} "/root/${SH} ${controller} ${OVERLAY_INTERFACE_IP_ADDRESS} ${PROVIDER_INTERFACE_NAME}"

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
