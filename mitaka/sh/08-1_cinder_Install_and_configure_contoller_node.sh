#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 0
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
CINDER_PASS=`get_passwd CINDER_PASS`
CINDER_DBPASS=`get_passwd CINDER_DBPASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

prerequisites() {
  sed -i "s/CINDER_DBPASS/${CINDER_DBPASS}/g" ../sql/cinder.sql

  # Create the cinder database and Grant proper access to the cinder database:
  echo
  echo "** Creating cinder database and cinder user..."
  echo

  mysql -u root -p${DATABASE_PASS} < ../sql/cinder.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create a cinder user:
  echo
  echo "** openstack user create --password <password> cinder"
  echo

  openstack user create --domain default --password ${CINDER_PASS} cinder

  # Add the admin role to the cinder user:
  echo
  echo "** openstack role add --project service --user cinder admin"
  echo

  openstack role add --project service --user cinder admin

  # Create the cinder service entities:
  #
  # Note : The Block Storage service requires both the volume and volumev2 services.
  # However, both services use the same API endpoint that references the Block Storage
  # version 2 API.

  echo
  echo "** openstack service create --name cinder for volume"
  echo


  openstack service create --name cinder \
    --description "OpenStack Block Storage" volume

  echo
  echo "** openstack service create --name cinder for volumev2"
  echo


  openstack service create --name cinderv2 \
    --description "OpenStack Block Storage" volumev2


  # Create the Block Storage service API endpoints:
  echo
  echo "** openstack endpoint create for volume"
  echo

  openstack endpoint create --region RegionOne \
    volume public http://${controller}:8776/v1/%\(tenant_id\)s

  openstack endpoint create --region RegionOne \
    volume internal http://${controller}:8776/v1/%\(tenant_id\)s

  openstack endpoint create --region RegionOne \
    volume admin http://${controller}:8776/v1/%\(tenant_id\)s
    
  openstack endpoint create --region RegionOne \
    volumev2 public http://${controller}:8776/v2/%\(tenant_id\)s
    
  openstack endpoint create --region RegionOne \
    volumev2 internal http://${controller}:8776/v2/%\(tenant_id\)s

  openstack endpoint create --region RegionOne \
    volumev2 admin http://${controller}:8776/v2/%\(tenant_id\)s

}

install_and_configure_components () {

  # To install and configure Block Storage controller components
  # Install the packages:
  echo
  echo "** Installing the packages..."
  echo

  yum -y -q install openstack-cinder python-cinderclient python-oslo-db

  # Edit the /etc/cinder/cinder.conf file and complete the following actions:
  CONF=/etc/cinder/cinder.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  # Copy the /usr/share/cinder/cinder-dist.conf file to ${CONF}.
  cp /usr/share/cinder/cinder-dist.conf ${CONF}
  chown -R cinder:cinder ${CONF}

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://cinder:${CINDER_DBPASS}@${controller}/cinder

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
  openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username cinder
  openstack-config --set ${CONF} keystone_authtoken password ${CINDER_PASS}

  # In the [DEFAULT] section, configure the my_ip option to use the management interface
  openstack-config --set ${CONF} DEFAULT my_ip ${block}

  # In the [oslo_concurrency] section, configure the lock path:
  openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/cinder/tmp

  # (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
  ### openstack-config --set ${CONF} DEFAULT verbose  True

  # Populate the Block Storage database:
  echo
  echo "cinder-manage db sync"
  echo

  su -s /bin/sh -c "cinder-manage db sync" cinder

}

finalize_installation() {

  # To finalize installation
  # Start the Block Storage services and configure them to start when the system boots:
  echo
  echo "** Starting cinder services..."
  echo

  systemctl restart openstack-nova-api.service
  systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
  systemctl start openstack-cinder-api.service openstack-cinder-scheduler.service

  systemctl status openstack-nova-api.service
  systemctl status openstack-cinder-api.service openstack-cinder-scheduler.service


  # List loaded extensions to verify successful launch of the cinder-server process:
  echo
  echo "** cinder service-list"
  echo

  sleep 5;

  cinder service-list
}

## main
prerequisites
install_and_configure_components
finalize_installation

echo
echo "Done."