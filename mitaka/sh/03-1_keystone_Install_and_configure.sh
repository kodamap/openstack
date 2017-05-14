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

prerequisites () {

  # Create the keystone database and Grant proper access to the keystone database:
  echo
  echo "** Creating keystone database and keystone user..."
  echo

  sed -i "s/KEYSTONE_DBPASS/${KEYSTONE_DBPASS}/g" ../sql/keystone.sql
  mysql -u root -p${DATABASE_PASS} < ../sql/keystone.sql

}

install_configure_components () {

  yum -y install openstack-keystone httpd mod_wsgi

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
  openstack-config --set ${CONF} database connection mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${controller}/keystone

  # In the [token] section, configure the Fernet token provider:
  openstack-config --set ${CONF} token provider fernet

  # (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
  ## openstack-config --set ${CONF} DEFAULT verbose True

  # Populate the Identity service database:
  echo
  echo "** keystone-manage db_sync..."
  echo

  su -s /bin/sh -c "keystone-manage db_sync" keystone

  # Initialize Fernet keys:
  echo
  echo "keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone"
  echo

  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

}

configure_http_server () {

  # To configure the Apache HTTP server
  # Edit the /etc/httpd/conf/httpd.conf file and configure the ServerName option to reference the controller node:
  CONF=/etc/httpd/conf/httpd.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  sed -i "/^\#ServerName www.example.com:80$/a ServerName ${controller}" ${CONF}

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
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>
EOF

  # To finalize installation
  # Restart the Apache HTTP server:
  echo
  echo "** Restarting the Apache HTTP server"
  echo

  systemctl enable httpd.service
  systemctl start httpd.service
  systemctl status httpd.service

}

# main
prerequisites
install_configure_components
configure_http_server

echo "** Done."
