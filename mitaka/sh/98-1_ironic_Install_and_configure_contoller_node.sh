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
IRONIC_PASS=`get_passwd IRONIC_PASS`
IRONIC_DBPASS=`get_passwd IRONIC_DBPASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`


prerequisites () {

  # Create the ironic database and Grant proper access to the ironic database:
  echo
  echo "** Creating ironic database and ironic user..."
  echo

  sed -i "s/IRONIC_DBPASS/${IRONIC_DBPASS}/g" ../sql/ironic.sql
  mysql -u root -p${DATABASE_PASS} < ../sql/ironic.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # To create the service credentials, complete these steps:
  echo
  echo "** Creating the ironic user..."
  echo

  # Create the ironic user:
  openstack user create --domain default --password ${IRONIC_PASS} ironic
  openstack role add --project service --user ironic admin


  # Add the admin role to the ironic user:
  echo
  echo "** Adding the admin role to the ironic user and service project..."
  echo

  openstack role add --project service --user ironic admin

  # Create the ironic service entity:
  echo
  echo "** Creating the ironic service entity..."
  echo

  openstack service create --name ironic \
  --description "Ironic baremetal provisioning service" baremetal

  # Create the Compute service API endpoint:
  echo
  echo "** Creating the Compute service API endpoint..."
  echo

  openstack endpoint create --region RegionOne \
    baremetal admin http://${controller}:6385
  openstack endpoint create --region RegionOne \
    baremetal public http://${controller}:6385
  openstack endpoint create --region RegionOne \
    baremetal internal http://${controller}:6385

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

  yum -y install openstack-ironic-api openstack-ironic-conductor python-ironicclient


  # Edit the /etc/ironic/ironic.conf file and complete the following actions:
  CONF=/etc/ironic/ironic.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] sections, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://ironic:${IRONIC_DBPASS}@${controller}/ironic?charset=utf8

  # In the [DEFAULT] section, enable only the compute and metadata APIs:
  openstack-config --set ${CONF} DEFAULT enabled_apis osapi_compute,metadata

  # In the [DEFAULT] and [oslo_messaging_rabbit] sections, configure RabbitMQ message queue access:
  openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_host ${controller}
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_userid openstack
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_password ${RABBIT_PASS}

  # In the [DEFAULT] and [keystone_authtoken] sections, configure Identity service access:
  # Note : Comment out or remove any other options in the [keystone_authtoken] section.
  openstack-config --set ${CONF} DEFAULT auth_strategy keystone
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken identity_uri http://${controller}:35357
  # openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  # openstack-config --set ${CONF} keystone_authtoken auth_type password
  # openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  # openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  # openstack-config --set ${CONF} keystone_authtoken project_name service
  # openstack-config --set ${CONF} keystone_authtoken username ironic
  # openstack-config --set ${CONF} keystone_authtoken password ${IRONIC_PASS}
  openstack-config --set ${CONF} keystone_authtoken admin_user ironic
  openstack-config --set ${CONF} keystone_authtoken admin_password ${IRONIC_PASS}
  openstack-config --set ${CONF} keystone_authtoken admin_tenant_name service

  # Populatie the Compute database
  echo
  echo "** ironic-manage api_db and db sync..."
  echo
  su -s /bin/sh -c "ironic-dbsync --config-file /etc/ironic/ironic.conf create_schema"

  # To finalize installation
  # Start the Compute services and configure them to start when the system boots:
  echo
  echo "** Starting the ironic services"
  echo

  systemctl enable openstack-ironic-api openstack-ironic-conductor
  systemctl start openstack-ironic-api openstack-ironic-conductor
  systemctl status openstack-ironic-api openstack-ironic-conductor
  
  echo
  echo "** ironic service-list"
  echo

  ironic service-list

}

# main
prerequisites
install_configure_components

echo
echo "Done."
