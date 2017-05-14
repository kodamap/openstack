#!/bin/sh -e

export LANG=en_US.utf8

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
GLANCE_PASS=`get_passwd GLANCE_PASS`
GLANCE_DBPASS=`get_passwd GLANCE_DBPASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

prerequisites () {

  # Create the glance database and Grant proper access to the glance database:
  echo
  echo "** Creating glance database and glance user..."
  echo

  sed -i "s/GLANCE_DBPASS/${GLANCE_DBPASS}/g" ../sql/glance.sql
  mysql -u root -p${DATABASE_PASS} < ../sql/glance.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create the glance user:
  echo
  echo "** Creating the glance user..."
  echo

  openstack user create --domain default --password ${GLANCE_PASS} glance

  # Add the admin role to the glance user and service project:
  echo
  echo "** Add the admin role to the glance user and service project..."
  echo

  openstack role add --project service --user glance admin

  # Create the glance service entity:
  echo
  echo "** Creating the glance service entity..."
  echo

  openstack service create --name glance \
    --description "OpenStack Image service" image

  # Create the Image service API endpoint:
  echo
  echo "** Creating the Image service API endpoint..."
  echo

  openstack endpoint create --region RegionOne \
    image public http://${controller}:9292

  openstack endpoint create --region RegionOne \
    image internal http://${controller}:9292

  openstack endpoint create --region RegionOne \
    image admin http://${controller}:9292

  echo
  echo "** openstack service list"
  echo

  openstack service list

}

install_configure_components () {

  # To install and configure the Image service components
  # Install the packages:
  echo
  echo "** Installing the packages..."
  echo

  yum -y install openstack-glance

  # Edit the /etc/glance/glance-api.conf file and complete the following actions:
  CONF=/etc/glance/glance-api.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${controller}/glance

  # In the [keystone_authtoken] and [paste_deploy] sections, configure Identity service access:
  # Note : Comment out or remove any other options in the [keystone_authtoken] section.
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken memcached_server ${contoller}:11211
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username glance
  openstack-config --set ${CONF} keystone_authtoken password ${GLANCE_PASS}
  openstack-config --set ${CONF} paste_deploy flavor keystone

  # In the [glance_store] section, configure the local file system store and location of image files:
  openstack-config --set ${CONF} glance_store stores file,http
  openstack-config --set ${CONF} glance_store default_store file
  openstack-config --set ${CONF} glance_store filesystem_store_datadir /var/lib/glance/images/

  # (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
  ## openstack-config --set ${CONF} DEFAULT verbose True

  # Edit the /etc/glance/glance-registry.conf file and complete the following actions:
  CONF=/etc/glance/glance-registry.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${controller}/glance

  # In the [keystone_authtoken] and [paste_deploy] sections, configure Identity service access:
  # Note : Comment out or remove any other options in the [keystone_authtoken] section.
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username glance
  openstack-config --set ${CONF} keystone_authtoken password ${GLANCE_PASS}
  openstack-config --set ${CONF} paste_deploy flavor keystone

  # Populate the Identity service database:
  echo
  echo "** glance-manage db_sync..."
  echo

  su -s /bin/sh -c "glance-manage db_sync" glance

  # To finalize installation
  # Start the Image service services and configure them to start when the system boots:
  echo
  echo "** Starting the glance services"
  echo

  systemctl enable openstack-glance-api.service openstack-glance-registry.service
  systemctl start openstack-glance-api.service openstack-glance-registry.service
  systemctl status openstack-glance-api.service openstack-glance-registry.service

}

# main
prerequisites
install_configure_components

echo
echo "Done."
