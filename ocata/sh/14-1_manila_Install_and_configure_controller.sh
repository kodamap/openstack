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
MANILA_PASS=`get_passwd MANILA_PASS`
MANILA_DBPASS=`get_passwd MANILA_DBPASS`
MANILA_DOMAIN_PASS=`get_passwd MANILA_DOMAIN_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`


prerequisites () {

  # Create the manila database and Grant proper access to the manila database:
  echo
  echo "** Creating manila database and manila user..."
  echo

  sed -i "s/MANILA_DBPASS/${MANILA_DBPASS}/g" ../sql/manila.sql
  mysql -u root -p${DATABASE_PASS} < ../sql/manila.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # To create the service credentials, complete these steps:
  echo
  echo "** Creating the manila user..."
  echo

  # Create the manila user:
  openstack user create --domain default --password ${MANILA_PASS} manila

  # Add the admin role to the manila user:
  echo
  echo "** Adding the admin role to the manila user and service project..."
  echo

  openstack role add --project service --user manila admin

  # Create the manila and manilav2 service entities:
  echo
  echo "** Creating the Manila service entity..."
  echo

  openstack service create --name manila \
  --description "OpenStack Shared File Systems" share
  
  openstack service create --name manilav2 \
  --description "OpenStack Shared File Systems" sharev2
  
  # Create the Shared File Systems service API endpoints:
  echo
  echo "** Creating the Manila service API endpoint..."
  echo

  openstack endpoint create --region RegionOne \
  share public http://${controller}:8786/v1/%\(tenant_id\)s
  
  openstack endpoint create --region RegionOne \
  share internal http://${controller}:8786/v1/%\(tenant_id\)s
  
  openstack endpoint create --region RegionOne \
  share admin http://${controller}:8786/v1/%\(tenant_id\)s

  openstack endpoint create --region RegionOne \
  sharev2 public http://${controller}:8786/v2/%\(tenant_id\)s
  
  openstack endpoint create --region RegionOne \
  sharev2 internal http://${controller}:8786/v2/%\(tenant_id\)s
  
  openstack endpoint create --region RegionOne \
  sharev2 admin http://${controller}:8786/v2/%\(tenant_id\)s
  

  echo
  echo "** openstack service list"
  echo

  openstack service list

}

install_configure_components () {

  # To install and configure Compute controller components
  # Install the packages
  echo
  echo "** Installing the packages..."
  echo

  yum install openstack-manila python-manilaclient -y

  # Edit the /etc/manila/manila.conf file and complete the following actions:
  CONF=/etc/manila/manila.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://manila:${MANILA_DBPASS}@${controller}/manila
  
  # In the [DEFAULT] section, configure RabbitMQ message queue access:
  openstack-config --set ${CONF} DEFAULT transport_url rabbit://guest:guest@${controller}
  #openstack-config --set ${CONF} DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${controller}
  openstack-config --set ${CONF} DEFAULT default_share_type default_share_type
  openstack-config --set ${CONF} DEFAULT share_name_template share-%s
  openstack-config --set ${CONF} DEFAULT rootwrap_config /etc/manila/rootwrap.conf
  openstack-config --set ${CONF} DEFAULT api_paste_config /etc/manila/api-paste.ini
  
  # In the [DEFAULT] and [keystone_authtoken] sections, configure Identity service access:
  openstack-config --set ${CONF} DEFAULT auth_strategy keystone
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} keystone_authtoken project_domain_id default
  openstack-config --set ${CONF} keystone_authtoken user_domain_id default
  #openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken project_name services
  openstack-config --set ${CONF} keystone_authtoken username manila
  openstack-config --set ${CONF} keystone_authtoken password ${MANILA_PASS}

  # In the [DEFAULT] section, configure the my_ip option to use the management interface IP address of the controller node:
  openstack-config --set ${CONF} DEFAULT my_ip ${controller}

  # In the [oslo_concurrency] section, configure the lock path:
  openstack-config --set ${CONF} oslo_concurrency lock_path /var/lock/manila

  # (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
  ### openstack-config --set ${CONF} DEFAULT verbose  True

  # Populatie the Compute database
  echo
  echo "** manila-manage db sync..."
  echo
  su -s /bin/sh -c "manila-manage db sync" manila

  # To finalize installation
  # Start the Manila services and configure them to start when the system boots:
  echo
  echo "** Starting the Manila services"
  echo

  systemctl enable openstack-manila-api.service openstack-manila-scheduler.service
  systemctl start openstack-manila-api.service openstack-manila-scheduler.service
  systemctl status openstack-manila-api.service openstack-manila-scheduler.service

  echo
  echo "** manila service-list"
  echo

  manila service-list

}

# main
prerequisites
install_configure_components

echo
echo "Done."
