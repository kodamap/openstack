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
SWIFT_PASS=`get_passwd SWIFT_PASS`

prerequisites () {
  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc
  
  # Create a swift user:
  echo
  echo "** openstack user create swift"
  echo
  
  openstack user create --domain default --password ${SWIFT_PASS} swift
  
  # Add the admin role to the swift user:
  echo
  echo "** openstack role add --project service --user swift admin"
  echo
  
  openstack role add --project service --user swift admin

  # Create the swift service entity:
  echo
  echo "** openstack service create --name swift"
  echo
  
  openstack service create --name swift --description "OpenStack Object Storage" object-store
  
  # Create the Object Storage service API endpoint:
  echo
  echo "** openstack endpoint create.."
  echo

  openstack endpoint create --region RegionOne object-store public http://${controller}:8080/v1/AUTH_%\(tenant_id\)s
  openstack endpoint create --region RegionOne object-store internal http://${controller}:8080/v1/AUTH_%\(tenant_id\)s
  openstack endpoint create --region RegionOne object-store admin http://${controller}:8080/v1
  
}

install_components () {

  # To install and configure the controller node components
  # Install the packages:
  echo
  echo "** Installing the packages..."
  echo

  yum -y install openstack-swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware memcached
  

  # Obtain the proxy service configuration file from the Object Storage source repository:
  echo
  echo "** Obtain the proxy service configuration file..."
  echo

  curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/mitaka
    
  # Edit the /etc/swift/proxy-server.conf file and complete the following actions:
  CONF=/etc/swift/proxy-server.conf
  echo
  echo "** Editing the ${CONF}..."
  echo
    
  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [DEFAULT] section, configure the bind port, user, and configuration directory:
  openstack-config --set ${CONF} DEFAULT bind_port 8080
  openstack-config --set ${CONF} DEFAULT user swift
  openstack-config --set ${CONF} DEFAULT swift_dir /etc/swift

  # In the [pipeline:main] section, enable the appropriate modules:
  openstack-config --set ${CONF} pipeline:main pipeline "catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server"
    
  # In the [app:proxy-server] section, enable automatic account creation:
  openstack-config --set ${CONF} app:proxy-server use egg:swift#proxy
  openstack-config --set ${CONF} app:proxy-server account_autocreate true


  # In the [filter:keystoneauth] section, configure the operator roles:
  openstack-config --set ${CONF} filter:keystoneauth use egg:swift#keystoneauth
  openstack-config --set ${CONF} filter:keystoneauth operator_roles admin,user

  # In the [filter:authtoken] section, configure Identity service access:
  openstack-config --set ${CONF} filter:authtoken paste.filter_factory keystonemiddleware.auth_token:filter_factory
  openstack-config --set ${CONF} filter:authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} filter:authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} filter:authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} filter:authtoken auth_type password
  openstack-config --set ${CONF} filter:authtoken project_domain_name default
  openstack-config --set ${CONF} filter:authtoken user_domain_name default
  openstack-config --set ${CONF} filter:authtoken project_name service
  openstack-config --set ${CONF} filter:authtoken username swift
  openstack-config --set ${CONF} filter:authtoken password ${SWIFT_PASS}
  openstack-config --set ${CONF} filter:authtoken delay_auth_decision true

  # In the [filter:cache] section, configure the memcached location:
  openstack-config --set ${CONF} filter:cache use egg:swift#memcache
  openstack-config --set ${CONF} filter:cache memcache_servers ${controller}:11211

  echo
  echo "** Done."
  echo
}

## main
prerequisites
install_components