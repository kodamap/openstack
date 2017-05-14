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
NOVA_PASS=`get_passwd NOVA_PASS`
NOVA_DBPASS=`get_passwd NOVA_DBPASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# Create the nova database and Grant proper access to the nova database:
echo
echo "** Creating nova database and nova user..."
echo

sed -i "s/NOVA_DBPASS/${NOVA_DBPASS}/g" ../sql/nova.sql
mysql -u root -p${DATABASE_PASS} < ../sql/nova.sql

# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# To create the service credentials, complete these steps:
echo
echo "** Creating the nova user..."
echo

# Create the nova user:
openstack user create --password ${NOVA_PASS} nova

# Add the admin role to the nova user:
echo
echo "** Adding the admin role to the nova user and service project..."
echo

openstack role add --project service --user nova admin

# Create the nova service entity:
echo
echo "** Creating the nova service entity..."
echo

openstack service create --name nova \
  --description "OpenStack Compute" compute

# Create the Compute service API endpoint:
echo
echo "** Creating the Compute service API endpoint..."
echo

openstack endpoint create \
  --publicurl http://${controller}:8774/v2/%\(tenant_id\)s \
  --internalurl http://${controller}:8774/v2/%\(tenant_id\)s \
  --adminurl http://${controller}:8774/v2/%\(tenant_id\)s \
  --region RegionOne \
  compute
  
echo
echo "** openstack service list"
echo

openstack service list


# To install and configure Compute controller components
# Install the packages
echo
echo "** Installing the packages..."
echo

yum -y -q install openstack-nova-api openstack-nova-cert openstack-nova-conductor \
  openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler \
  python-novaclient

# Edit the /etc/nova/nova.conf file and complete the following actions:
CONF=/etc/nova/nova.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [database] section, configure database access:
openstack-config --set ${CONF} database connection mysql://nova:${NOVA_DBPASS}@${controller}/nova

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

# In the [DEFAULT] section, configure the my_ip option to use the management
# interface IP address of the controller node:
openstack-config --set ${CONF} DEFAULT my_ip ${controller}

# In the [DEFAULT] section, configure the VNC proxy to use the management
# interface IP address of the controller node:
openstack-config --set ${CONF} DEFAULT vncserver_listen ${controller}
openstack-config --set ${CONF} DEFAULT vncserver_proxyclient_address ${controller}

# In the [glance] section, configure the location of the Image service
openstack-config --set ${CONF} glance host ${controller}

# In the [oslo_concurrency] section, configure the lock path:
openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/nova/tmp

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True

# Populatie the Compute database
echo
echo "** nova-manage db sync..."
echo
su -s /bin/sh -c "nova-manage db sync" nova

# To finalize installation
# Start the Compute services and configure them to start when the system boots:
echo
echo "** Starting the nova services"
echo

systemctl enable openstack-nova-api.service openstack-nova-cert.service \
  openstack-nova-consoleauth.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service
systemctl start openstack-nova-api.service openstack-nova-cert.service \
  openstack-nova-consoleauth.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service
systemctl status openstack-nova-api.service openstack-nova-cert.service \
  openstack-nova-consoleauth.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service


echo
echo "** nova service-list"
echo

nova service-list

echo
echo "Done."