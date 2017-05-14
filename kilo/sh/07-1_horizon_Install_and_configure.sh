#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

# Install the packages
echo
echo "** Installing the packages..."
echo
yum -y -q install openstack-dashboard httpd mod_wsgi memcached python-memcached

# To configure the dashboard
# Edit the /etc/openstack-dashboard/local_settings file and complete the following actions:
CONF=/etc/openstack-dashboard/local_settings
echo
echo "** Editing the ${CONF}..."

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

sed -i "s/^OPENSTACK_HOST = \"127.0.0.1\"$/OPENSTACK_HOST = \"${controller}\"/" ${CONF}
sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = \['*', \]/" ${CONF}
sed -i "127,131s/^/#/" ${CONF}
sed -i "120,125s/^#//" ${CONF}
sed -i "s/^OPENSTACK_KEYSTONE_DEFAULT_ROLE = .*/OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"/" ${CONF}
sed -i "s/^TIME_ZONE = .*/TIME_ZONE = \"Asia\/Tokyo\"/" ${CONF}

# Edit the /usr/share/openstack-dashboard/openstack_dashboard/settings.py file and complete the following actions:
## Bug 1221117 - Horizon: Re login failed after timeout
echo "** To fix the Bug 1221117 - Horizon: Re login failed after timeout **"
CONF=/usr/share/openstack-dashboard/openstack_dashboard/settings.py
echo
echo "** Editing the ${CONF}..."

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

sed -i "/^AUTHENTICATION_URLS = .*/a AUTH_USER_MODEL = 'openstack_auth.User'" ${CONF}


# To finalize installation

# On RHEL and CentOS, configure SELinux to permit the web server to connect to OpenStack services:
setsebool -P httpd_can_network_connect on

# Due to a packaging bug, the dashboard CSS fails to load properly.
# Run the following command to resolve this issue:
chown -R apache:apache /usr/share/openstack-dashboard/static

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

echo
echo "Done."
