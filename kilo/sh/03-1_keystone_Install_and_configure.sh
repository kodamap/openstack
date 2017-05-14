#!/bin/sh -e

export LANG=en_US.utf8

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
KEYSTONE_DBPASS=`get_passwd KEYSTONE_DBPASS`

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

# Create the keystone database and Grant proper access to the keystone database:
echo
echo "** Creating keystone database and keystone user..."
echo

sed -i "s/KEYSTONE_DBPASS/${KEYSTONE_DBPASS}/g" ../sql/keystone.sql
mysql -u root -p${DATABASE_PASS} < ../sql/keystone.sql

# Install the packages:

echo
echo "** Installing the packages..."
echo

yum -y -q install openstack-keystone httpd mod_wsgi python-openstackclient memcached python-memcached

systemctl enable memcached.service
systemctl start memcached.service
systemctl status memcached.service

# Edit the /etc/keystone/keystone.conf file and complete the following actions:
CONF=/etc/keystone/keystone.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# Generate a random value to use as the administration token during initial configuration:
ADMIN_TOKEN=`openssl rand -hex 10`

# In the [DEFAULT] section, define the value of the initial administration token:
openstack-config --set ${CONF} DEFAULT admin_token ${ADMIN_TOKEN}

# In the [database] section, configure database access:
openstack-config --set ${CONF} database connection mysql://keystone:${KEYSTONE_DBPASS}@${controller}/keystone

# In the [memcache] section, configure the Memcache service:
openstack-config --set ${CONF} memcache servers localhost:11211

# In the [token] section, configure the UUID token provider and Memcached driver:
openstack-config --set ${CONF} token provider keystone.token.providers.uuid.Provider
openstack-config --set ${CONF} token driver keystone.token.persistence.backends.memcache.Token

# In the [revoke] section, configure the SQL revocation driver:
openstack-config --set ${CONF} revoke driver keystone.contrib.revoke.backends.sql.Revoke

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
## openstack-config --set ${CONF} DEFAULT verbose True

# Populate the Identity service database:
echo
echo "** keystone-manage db_sync..."
echo

su -s /bin/sh -c "keystone-manage db_sync" keystone

# To configure the Apache HTTP server
# Edit the /etc/httpd/conf/httpd.conf file and configure the ServerName option to reference the controller node:
CONF=/etc/httpd/conf/httpd.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

sed -i "/^\#ServerName www.example.com:80$/a ServerName ${controller}:80" ${CONF}

# Create the /etc/httpd/conf.d/wsgi-keystone.conf file with the following content:

CONF=/etc/httpd/conf.d/wsgi-keystone.conf
echo
echo "** Creating the ${CONF}..."
echo

cat <<'EOF' >/etc/httpd/conf.d/wsgi-keystone.conf
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /var/www/cgi-bin/keystone/main
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LogLevel info
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /var/www/cgi-bin/keystone/admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LogLevel info
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined
</VirtualHost>
EOF

# Create the directory structure for the WSGI components:
mkdir -p /var/www/cgi-bin/keystone

# Copy the WSGI components from the upstream repository into this directory:
curl http://git.openstack.org/cgit/openstack/keystone/plain/httpd/keystone.py?h=stable/kilo \
  | tee /var/www/cgi-bin/keystone/main /var/www/cgi-bin/keystone/admin

# Adjust ownership and permissions on this directory and the files in it:
chown -R keystone:keystone /var/www/cgi-bin/keystone
chmod 755 /var/www/cgi-bin/keystone/*

# To finalize installation
# Restart the Apache HTTP server:
echo
echo "** Restarting the Apache HTTP server"
echo

systemctl enable httpd.service
systemctl start httpd.service
systemctl status httpd.service

echo "** Done."