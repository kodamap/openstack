#!/bin/sh -e

export LANG=en_US.utf8

if [[ $# -ne 1 ]]; then
    echo "** Usage: $0 <controller IP>"
    exit 1
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
CEILOMETER_DBPASS=`get_passwd CEILOMETER_DBPASS`
CEILOMETER_PASS=`get_passwd CEILOMETER_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

prerequisites () {

  # Install the MongoDB packages:
  yum install mongodb-server mongodb -y
  
  # Edit the /etc/mongod.conf file and complete the following actions:
  CONF=/etc/mongod.conf
  echo
  echo "** Editing the ${CONF}..."
  echo
  
  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  sed -i "s/^bind_ip = 127.0.0.1$/bind_ip = ${controller}/" ${CONF}
  echo "smallfiles = true" >>  ${CONF}

  # Start the MongoDB service and configure it to start when the system boots:
  echo
  echo "** Starting mongod.service..."
  echo

  systemctl enable mongod.service
  systemctl start mongod.service
  systemctl status mongod.service
  
  # Create the ceilometer database:
  sed -i "s/CEILOMETER_DBPASS/${CEILOMETER_DBPASS}/g" ../lib/ceilodb.sh
  chmod +x ../lib/ceilodb.sh
  ../lib/ceilodb.sh
  
  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create the ceilometer user:
  echo
  echo "** Creating the ceilometer user..."
  echo

  openstack user create --domain default --password ${CEILOMETER_PASS} ceilometer

  # Add the admin role to the ceilometer user:
  echo
  echo "** Adding the admin role to the ceilometer user and service project..."
  echo

  openstack role add --project service --user ceilometer admin

  # Create the ceilometer service entity:
  echo
  echo "** Creating the ceilometer service entities..."
  echo

  openstack service create --name ceilometer --description "Telemetry" metering
  
  # Create the Telemetry service API endpoints:
  echo
  echo "** Creating the Telemetry service API endpoints..."
  echo

  openstack endpoint create --region RegionOne metering public http://${controller}:8777
  openstack endpoint create --region RegionOne metering internal http://${controller}:8777
  openstack endpoint create --region RegionOne metering admin http://${controller}:8777  
  
}

install_components () {

  # Install the packages
  echo
  echo "** Installing the packages..."
  echo

  yum -y install openstack-ceilometer-api \
  openstack-ceilometer-collector openstack-ceilometer-notification \
  openstack-ceilometer-central openstack-ceilometer-alarm \
  python-ceilometerclient
  
  # Edit the /etc/ceilometer/ceilometer.conf file and complete the following actions:

  CONF=/etc/ceilometer/ceilometer.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mongodb://ceilometer:${CEILOMETER_DBPASS}@${controller}:27017/ceilometer

  # In the [DEFAULT] and [oslo_messaging_rabbit] sections, configure RabbitMQ message queue access:
  openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_host ${controller}
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_userid openstack
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_password ${RABBIT_PASS}

  # In the [DEFAULT] and [keystone_authtoken] sections, configure Identity service access:

  openstack-config --set ${CONF} DEFAULT auth_strategy keystone
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken auth_plugin password
  openstack-config --set ${CONF} keystone_authtoken project_domain_id default
  openstack-config --set ${CONF} keystone_authtoken user_domain_id default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username ceilometer
  openstack-config --set ${CONF} keystone_authtoken password ${CEILOMETER_PASS}

  # In the [service_credentials] section, configure service credentials:
  openstack-config --set ${CONF} service_credentials os_auth_url http://controller:5000/v2.0
  openstack-config --set ${CONF} service_credentials os_username ceilometer
  openstack-config --set ${CONF} service_credentials os_password ${CEILOMETER_PASS}
  openstack-config --set ${CONF} service_credentials os_endpoint_type internalURL
  openstack-config --set ${CONF} service_credentials os_region_name RegionOne

}


finalize_installation () {

  # Start the Telemetry services and configure them to start when the system boots:

  echo
  echo "** starting ceilometer service..."
  echo

  systemctl enable openstack-ceilometer-api.service \
    openstack-ceilometer-notification.service \
    openstack-ceilometer-central.service \
    openstack-ceilometer-collector.service \
    openstack-ceilometer-alarm-evaluator.service \
    openstack-ceilometer-alarm-notifier.service  
  
  systemctl start openstack-ceilometer-api.service \
    openstack-ceilometer-notification.service \
    openstack-ceilometer-central.service \
    openstack-ceilometer-collector.service \
    openstack-ceilometer-alarm-evaluator.service \
    openstack-ceilometer-alarm-notifier.service

  systemctl status openstack-ceilometer-api.service \
    openstack-ceilometer-notification.service \
    openstack-ceilometer-central.service \
    openstack-ceilometer-collector.service \
    openstack-ceilometer-alarm-evaluator.service \
    openstack-ceilometer-alarm-notifier.service

}

#main
prerequisites
install_components
finalize_installation

echo
echo "Done."
