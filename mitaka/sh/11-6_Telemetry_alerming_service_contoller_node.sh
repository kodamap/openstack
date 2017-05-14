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
AODH_PASS=`get_passwd AODH_PASS`
AODH_DBPASS=`get_passwd AODH_DBPASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

prerequisites () {

  sed -i "s/AODH_DBPASS/${AODH_DBPASS}/g" ../sql/aodh.sql

  # Create the aodh database and Grant proper access to the aodh database:
  echo
  echo "** Creating aodh database and aodh user..."
  echo

  mysql -u root -p${DATABASE_PASS} < ../sql/aodh.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # To create the service credentials, complete these steps:
  # Create the aodh user:
  echo
  echo "** Creating the aodh user..."
  echo

  openstack user create --domain default --password ${AODH_PASS} aodh

  # Add the admin role to the aodh user:
  echo
  echo "** Adding the admin role to the aodh user and service project..."
  echo

  openstack role add --project service --user aodh admin

  # Create the aodh service entities:
  echo
  echo "** Creating the aodh service entities..."
  echo

  openstack service create --name aodh \
    --description "Telemetry" alarming
    
  # Create the Alarming service API endpoints:
  echo
  echo "** Creating the Alarming service API endpoints..."
  echo

  openstack endpoint create --region RegionOne \
    alarming public http://${controller}:8042
  
  openstack endpoint create --region RegionOne \
    alarming internal http://${controller}:8042
  
  openstack endpoint create --region RegionOne \
    alarming admin http://${controller}:8042

}

install_components () {

  # Install the packages
  echo
  echo "** Installing the packages..."
  echo

  yum install openstack-aodh-api \
  openstack-aodh-evaluator openstack-aodh-notifier \
  openstack-aodh-listener openstack-aodh-expirer \
  python-ceilometerclient -y
  
  # Edit the /etc/aodh/aodh.conf file and complete the following actions:
  CONF=/etc/aodh/aodh.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://aodh:${AODH_DBPASS}@${controller}/aodh

  # In the [DEFAULT] and [keystone_authtoken] sections, configure Identity service access:
  openstack-config --set ${CONF} DEFAULT auth_strategy keystone
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username aodh
  openstack-config --set ${CONF} keystone_authtoken password ${AODH_PASS}

  # In the [service_credentials] section, configure service credentials:
  openstack-config --set ${CONF} service_credentials auth_type password
  openstack-config --set ${CONF} service_credentials auth_url http://${controller}:5000/v3
  openstack-config --set ${CONF} service_credentials project_domain_name default
  openstack-config --set ${CONF} service_credentials user_domain_name default
  openstack-config --set ${CONF} service_credentials project_name service
  openstack-config --set ${CONF} service_credentials username aodh
  openstack-config --set ${CONF} service_credentials password ${AODH_PASS}
  openstack-config --set ${CONF} service_credentials interface internalURL
  openstack-config --set ${CONF} service_credentials region_name RegionOne
}


finalize_installation () {

  su -s /bin/sh -c "aodh-dbsync" aodh
  
  # Start the Alarming services and configure them to start when the system boots:

  echo
  echo "** starting Alerming service..."
  echo

  systemctl enable openstack-aodh-api.service \
  openstack-aodh-evaluator.service \
  openstack-aodh-notifier.service \
  openstack-aodh-listener.service
  
  systemctl start openstack-aodh-api.service \
  openstack-aodh-evaluator.service \
  openstack-aodh-notifier.service \
  openstack-aodh-listener.service

  systemctl status openstack-aodh-api.service \
  openstack-aodh-evaluator.service \
  openstack-aodh-notifier.service \
  openstack-aodh-listener.service


}

#main
prerequisites
install_components
finalize_installation

echo
echo "Done."
