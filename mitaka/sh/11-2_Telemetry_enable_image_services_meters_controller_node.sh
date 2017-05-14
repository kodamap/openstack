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

install_components () {

  # Configure the Image service to use Telemetry
  # Edit the /etc/glance/glance-api.conf and /etc/glance/glance-registry.conf 
  # files and complete the following actions:
  CONF=/etc/glance/glance-api.conf
  echo
  echo "** Editing the ${CONF}..."
  echo
  
  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [DEFAULT], [oslo_messaging_notifications], and [oslo_messaging_rabbit] sections,
  # configure notifications and RabbitMQ message broker access:
  openstack-config --set ${CONF} DEFAULT rpc_backend rabbit

  openstack-config --set ${CONF} oslo_messaging_notifications driver messagingv2

  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_host ${controller}
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_userid openstack
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_password ${RABBIT_PASS}
  
  # Restart the Image service:
  echo
  echo "** Restarting glance service..."
  echo
  
  systemctl restart openstack-glance-api.service openstack-glance-registry.service
  systemctl status openstack-glance-api.service openstack-glance-registry.service
}

finalize_installation () {

  # Restart the Image service:
  echo
  echo "** Restarting glance service..."
  echo
  
  systemctl restart openstack-glance-api.service openstack-glance-registry.service
  systemctl status openstack-glance-api.service openstack-glance-registry.service

}

#main
install_components
finalize_installation

echo
echo "Done."
