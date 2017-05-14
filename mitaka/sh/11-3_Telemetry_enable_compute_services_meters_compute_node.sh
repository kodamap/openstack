#!/bin/sh -e

export LANG=en_US.utf8

# To Fix it , Modify the paramters manually.

SH=install_and_configure_ceilometer.sh
PW_FILE=OPENSTACK_PASSWD.ini

function generate_ceilometer_sh {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

if [ $# -ne 1 ]; then
    echo "** Usage: $0 <controller ip>"
    exit 1
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
CEILOMETER_DBPASS=`get_passwd CEILOMETER_DBPASS`
CEILOMETER_PASS=`get_passwd CEILOMETER_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# To install the Telemetory components
echo
echo "** Installing the packages..."
echo

yum install openstack-ceilometer-compute python-ceilometerclient python-pecan -y
 
# Edit the /etc/ceilometer/ceilometer.conf file and complete the following actions:
CONF=/etc/ceilometer/ceilometer.conf
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
openstack-config --set ${CONF} DEFAULT auth_strategy keystone
openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
openstack-config --set ${CONF} keystone_authtoken auth_type password
openstack-config --set ${CONF} keystone_authtoken project_domain_name default
openstack-config --set ${CONF} keystone_authtoken user_domain_name default
openstack-config --set ${CONF} keystone_authtoken project_name service
openstack-config --set ${CONF} keystone_authtoken username ceilometer
openstack-config --set ${CONF} keystone_authtoken password ${CEILOMETER_PASS}

# In the [service_credentials] section, configure service credentials:
openstack-config --set ${CONF} service_credentials os_auth_url http://${controller}:5000/v2.0
openstack-config --set ${CONF} service_credentials os_username ceilometer
openstack-config --set ${CONF} service_credentials os_tenant_name service
openstack-config --set ${CONF} service_credentials os_password ${CEILOMETER_PASS}
openstack-config --set ${CONF} service_credentials interface internalURL
openstack-config --set ${CONF} service_credentials region_name RegionOne

# Configure Compute to use Telemetry
# Edit the /etc/nova/nova.conf file and configure notifications in the [DEFAULT] section:
CONF=/etc/nova/nova.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} DEFAULT instance_usage_audit True
openstack-config --set ${CONF} DEFAULT instance_usage_audit_period hour
openstack-config --set ${CONF} DEFAULT notify_on_state_change vm_and_task_state
openstack-config --set ${CONF} DEFAULT notification_driver messagingv2

# To finalize the installation

# Start the agent and configure it to start when the system boots:
echo
echo "** Starting ceilometer agent service..."
echo

systemctl enable openstack-ceilometer-compute.service
systemctl start openstack-ceilometer-compute.service
systemctl status openstack-ceilometer-compute.service

# Restart the Compute service:
echo
echo "** Restarting nova compute service"
echo

systemctl restart openstack-nova-compute.service
systemctl status openstack-nova-compute.service

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main


if [ $# -ne 2 ]; then
    echo "** Usage: $0 <controller node ip> <compute ip>"
    exit 1
fi

controller=$1
compute=$2

ssh-copy-id root@${compute}
generate_ceilometer_sh
chmod 755 ../lib//${SH}
scp -p ${PW_FILE} root@${compute}:/root/
scp -p ../lib//${SH} root@${compute}:/root/
ssh root@${compute} "/root/${SH} ${controller}"

# Verify operation
# Source the admin credentials to gain access to admin-only CLI commands:
# source ~/admin-openrc


echo
echo "Done."
