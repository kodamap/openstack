#!/bin/sh -e

export LANG=en_US.utf8

SH=install_and_configure_compute.sh
PW_FILE=OPENSTACK_PASSWD.ini

function generate_compute_sh {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

if [ $# -ne 2 ]; then
   echo "** Usage: $0 <controller ip> <cumpute ip>"
   exit 1
fi

controller=$1
compute=$2

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
NOVA_PASS=`get_passwd NOVA_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# Install the packages:

echo
echo "** Installing the packages on `hostname`..."
echo

yum -y install openstack-utils
yum -y install openstack-nova-compute sysfsutils

# Edit the /etc/nova/nova.conf file and complete the following actions:
CONF=/etc/nova/nova.conf
echo
echo "** Editting ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

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
openstack-config --set ${CONF} keystone_authtoken username nova
openstack-config --set ${CONF} keystone_authtoken password ${NOVA_PASS}

# In the [DEFAULT] section, configure the my_ip option:
# my_ip is the IP address of the management network interface on your compute node.
openstack-config --set ${CONF} DEFAULT my_ip ${compute}

# In the [DEFAULT] section, enable support for the Networking service:
openstack-config --set ${CONF} DEFAULT network_api_class nova.network.neutronv2.api.API
openstack-config --set ${CONF} DEFAULT security_group_api neutron
openstack-config --set ${CONF} DEFAULT linuxnet_interface_driver nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver
openstack-config --set ${CONF} DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

# In the [vnc] section, enable and configure remote console access:
# NOTE:
# By default, Compute uses an internal firewall service. Since Networking includes a firewall service,
# you must disable the Compute firewall service by using the nova.virt.firewall.NoopFirewallDriver firewall driver.
openstack-config --set ${CONF} vnc enabled True
openstack-config --set ${CONF} vnc vncserver_listen 0.0.0.0
openstack-config --set ${CONF} vnc vncserver_proxyclient_address ${compute}
openstack-config --set ${CONF} vnc novncproxy_base_url http://${controller}:6080/vnc_auto.html

# In the [glance] section, configure the location of the Image service
openstack-config --set ${CONF} glance host ${controller}

# In the [oslo_concurrency] section, configure the lock path:
openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/nova/tmp

# To fix "VirtualInterfaceCreateException: Virtual Interface creation failed"
# https://ask.openstack.org/en/question/26938/virtualinterfacecreateexception-virtual-interface-creation-failed/
# openstack-config --set ${CONF} DEFAULT vif_plugging_is_fatal false
# openstack-config --set ${CONF} DEFAULT vif_plugging_timeout 0

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# If this command returns a value of zero, your compute node does not support hardware acceleration
# and you must configure libvirt to use QEMU instead of KVM
if [[ `egrep -c '(vmx|svm)' /proc/cpuinfo` -eq 0 ]] ; then
    sed -i "/^\[libvirt\]$/a virt_type = qemu" /etc/nova/nova.conf
fi

# Start the Compute service including its dependencies and configure them to start
# automatically when the system boots:
echo
echo "** Starting nova compute services on `hostname`..."
echo

systemctl enable libvirtd.service openstack-nova-compute.service
systemctl start libvirtd.service openstack-nova-compute.service
systemctl status libvirtd.service openstack-nova-compute.service

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}


# main

if [ $# -ne 2 ]; then
    echo "** Usage: $0 <controller node IP> <compute node ip>"
    exit 1
fi

controller=$1
compute=$2


ssh-copy-id root@${compute}
generate_compute_sh
chmod 755 ../lib//${SH}
scp -p ../lib//install_and_configure_compute.sh root@${compute}:/root/
scp -p ${PW_FILE} root@${compute}:/root/
ssh root@${compute} "/root/${SH} ${controller} ${compute}"

# Verify operation
# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# List service components to verify successful launch of each process:
echo
echo "** nova service-list"
echo

sleep 3;

nova service-list

echo
echo "Done."
