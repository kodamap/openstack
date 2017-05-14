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
CEILOMETER_DBPASS=`get_passwd CEILOMETER_DBPASS`
CEILOMETER_PASS=`get_passwd CEILOMETER_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

prerequisites () {

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create the ResellerAdmin role:
  openstack role create ResellerAdmin

  # Add the ResellerAdmin role to the ceilometer user:
  openstack role add --project service --user ceilometer ResellerAdmin

}

install_components () {
  
  # Install the packages:
  yum install python-ceilometermiddleware -y

  # Perform these steps on the controller and any other nodes that run the Object Storage proxy service.
  # Edit the /etc/swift/proxy-server.conf file and complete the following actions:
  CONF=/etc/swift/proxy-server.conf
  echo
  echo "** Editing the ${CONF}..."
  echo
  
  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [filter:keystoneauth] section, add the ResellerAdmin role:
  openstack-config --set ${CONF} filter:keystoneauth operator_roles admin, user, ResellerAdmin

  # In the [pipeline:main] section, add ceilometer:
  openstack-config --set ${CONF} pipeline:main pipeline "catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging ceilometer proxy-server"
  
  # In the [filter:ceilometer] section, configure notifications:
  openstack-config --set ${CONF} filter:ceilometer paste.filter_factory ceilometermiddleware.swift:filter_factory
  openstack-config --set ${CONF} filter:ceilometer control_exchange swift
  openstack-config --set ${CONF} filter:ceilometer url rabbit://openstack:${RABBIT_PASS}@${controller}:5672/
  openstack-config --set ${CONF} filter:ceilometer driver messagingv2
  openstack-config --set ${CONF} filter:ceilometer topic notifications
  openstack-config --set ${CONF} filter:ceilometer log_level WARN
}

finalize_installation () {

  # Restart the Object Storage proxy service:
  
  echo
  echo "** starting s service..."
  echo

  systemctl restart openstack-swift-proxy.service
  systemctl status openstack-swift-proxy.service

}

#main
prerequisites
install_components
finalize_installation

echo
echo "Done."
