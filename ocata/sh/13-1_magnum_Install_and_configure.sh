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
MAGNUM_PASS=`get_passwd MAGNUM_PASS`
MAGNUM_DBPASS=`get_passwd MAGNUM_DBPASS`
MAGNUM_DOMAIN_PASS=`get_passwd MAGNUM_DOMAIN_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`


prerequisites () {

  # Create the magnum database and Grant proper access to the magnum database:
  echo
  echo "** Creating magnum database and magnum user..."
  echo

  sed -i "s/MAGNUM_DBPASS/${MAGNUM_DBPASS}/g" ../sql/magnum.sql
  mysql -u root -p${DATABASE_PASS} < ../sql/magnum.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # To create the service credentials, complete these steps:
  echo
  echo "** Creating the magnum user..."
  echo

  # Create the magnum user:
  openstack user create --domain default --password ${MAGNUM_PASS} magnum

  # Add the admin role to the magnum user:
  echo
  echo "** Adding the admin role to the magnum user and service project..."
  echo

  openstack role add --project service --user magnum admin

  # Create the magnum service entity:
  echo
  echo "** Creating the Magnum service entity..."
  echo

  openstack service create --name magnum \
  --description "OpenStack Container Infrastructure Management Service" container-infra
  
  # Create the Magnum service API endpoint:
  echo
  echo "** Creating the Magnum service API endpoint..."
  echo

  openstack endpoint create --region RegionOne \
    container-infra public http://${controller}:9511/v1
  
  openstack endpoint create --region RegionOne \
    container-infra internal http://${controller}:9511/v1
 
  openstack endpoint create --region RegionOne \
    container-infra admin http://${controller}:9511/v1

  # Magnum requires additional information in the Identity service to manage COE clusters. 
  # To add this information, complete these steps:
  
  # Create the magnum domain that contains projects and users:
  openstack domain create --description "Owns users and projects created by magnum" magnum

  # Create the magnum_domain_admin user to manage projects and users in the magnum domain:
  openstack user create --domain magnum --password ${MAGNUM_DOMAIN_PASS} magnum_domain_admin

  # Add the admin role to the magnum_domain_admin user in the magnum domain to enable administrative management privileges by the magnum_domain_admin user:
  openstack role add --domain magnum --user magnum_domain_admin admin
  
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

  yum -y install openstack-magnum-api openstack-magnum-conductor

  # Edit the /etc/magnum/magnum.conf file and complete the following actions:
  CONF=/etc/magnum/magnum.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [api] section, configure the host:
  openstack-config --set ${CONF} api host ${controller}

  # In the [certificates] section, select barbican (or x509keypair if you donft have barbican installed):
  #  Important
  # Barbican is recommended for production environments.
  openstack-config --set ${CONF} certificates cert_manager_type x509keypair

  # In the [cinder_client] section, configure the region name:
  openstack-config --set ${CONF} cinder_client region_name RegionOne

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://magnum:${MAGNUM_DBPASS}@${controller}/magnum
  
  # In the [keystone_authtoken] and [trust] sections, configure Identity service access:
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken auth_version v3
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000/v3
  openstack-config --set ${CONF} keystone_authtoken project_domain_id default
  openstack-config --set ${CONF} keystone_authtoken project_name services
  openstack-config --set ${CONF} keystone_authtoken user_domain_id default
  openstack-config --set ${CONF} keystone_authtoken password ${MAGNUM_PASS}
  openstack-config --set ${CONF} keystone_authtoken username magnum
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} trust trustee_domain_name magnum
  openstack-config --set ${CONF} trust trustee_domain_admin_name magnum_domain_admin
  openstack-config --set ${CONF} trust trustee_domain_admin_password ${MAGNUM_DOMAIN_PASS}

  # In the [oslo_messaging_notifications] section, configure the driver:
  openstack-config --set ${CONF} oslo_messaging_notifications driver messaging
  
  # In the [DEFAULT] section, configure RabbitMQ message queue access:
  openstack-config --set ${CONF} DEFAULT transport_url rabbit://guest:guest@${controller}

  # openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_host ${controller} password
  # openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_userid guest
  # openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_password guest

  # In the [oslo_concurrency] section, configure the lock_path:
  openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/magnum/tmp
  # (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
  ### openstack-config --set ${CONF} DEFAULT verbose  True

  # Populatie the Compute database
  echo
  echo "** magnum-manage db sync..."
  echo
  su -s /bin/sh -c "magnum-db-manage upgrade" magnum

  # To finalize installation
  # Start the Magnum services and configure them to start when the system boots:
  echo
  echo "** Starting the Magnum services"
  echo

  systemctl enable openstack-magnum-api.service openstack-magnum-conductor.service
  systemctl start openstack-magnum-api.service openstack-magnum-conductor.service
  systemctl status openstack-magnum-api.service openstack-magnum-conductor.service

  echo
  echo "** magnum service-list"
  echo

  magnum service-list

}

# main
prerequisites
install_configure_components

echo
echo "Done."
