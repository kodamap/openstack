#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

install_configure_components () {

  # Install the packages
  echo
  echo "** Installing the packages..."
  echo
  yum -y install openstack-dashboard

  # To configure the dashboard
  # Edit the /etc/openstack-dashboard/local_settings file and complete the following actions:
  CONF=/etc/openstack-dashboard/local_settings
  echo
  echo "** Editing the ${CONF}..."

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org
  
  # Configure the dashboard to use OpenStack services on the controller node:
  sed -i "s/^OPENSTACK_HOST = \"127.0.0.1\"$/OPENSTACK_HOST = \"${controller}\"/" ${CONF}
  # Allow all hosts to access the dashboard:
  sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = \['*', \]/" ${CONF}
  sed -i "135,139s/^/#/" ${CONF}
  ##sed -i "120,125s/^#//" ${CONF}
  # Enable the Identity API version 3:
  sed -i "s/^OPENSTACK_KEYSTONE_URL = .*/OPENSTACK_KEYSTONE_URL = \"http:\/\/\%s:5000\/v3\"\ \%\ OPENSTACK_HOST/" ${CONF}
  # Enable support for domains:
  sed -i "s/^#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = .*/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/" ${CONF}
  sed -i "s/^#OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = .*/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"default\"/" ${CONF}
  sed -i "s/^OPENSTACK_KEYSTONE_DEFAULT_ROLE = .*/OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"/" ${CONF}

  cat <<EOF >> ${CONF}

# Configure the memcached session storage service:
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'

CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': '${controller}:11211',
    }
}

# Configure API versions:
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}
EOF
  sed -i "s/^TIME_ZONE = .*/TIME_ZONE = \"Asia\/Tokyo\"/" ${CONF}

}

finalize_installation () {

  # To finalize installation

  # On RHEL and CentOS, configure SELinux to permit the web server to connect to OpenStack services:
  ## setsebool -P httpd_can_network_connect on

  # Due to a packaging bug, the dashboard CSS fails to load properly.
  # Run the following command to resolve this issue:
  ## chown -R apache:apache /usr/share/openstack-dashboard/static

  # Start the web server and session storage service and configure them to start when the system boots:
  echo
  echo "** Starting the web server and session storage service"
  echo

  systemctl enable httpd.service memcached.service
  systemctl restart httpd.service memcached.service
  systemctl status httpd.service memcached.service

  echo
  echo "** Starded httpd service"
  echo "** Access the dashboard using a web browser: http://${controller}/dashboard ."
  echo "** Authenticate using admin or demo user credentials."
  echo

}

# main
install_configure_components
finalize_installation

echo
echo "Done."
