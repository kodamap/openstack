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
HEAT_DBPASS=`get_passwd HEAT_DBPASS`
HEAT_DOMAIN_PASS=`get_passwd HEAT_DOMAIN_PASS`
HEAT_PASS=`get_passwd HEAT_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

prerequisites () {

  sed -i "s/HEAT_DBPASS/${HEAT_DBPASS}/g" ../sql/heat.sql

  # Create the heat database and Grant proper access to the heat database:
  echo
  echo "** Creating heat database and heat user..."
  echo

  mysql -u root -p${DATABASE_PASS} < ../sql/heat.sql

  # Source the admin credentials to gain access to admin-only CLI commands:
  source ~/admin-openrc

  # Create the heat user:
  echo
  echo "** Creating the heat user..."
  echo

  openstack user create --domain default --password ${HEAT_PASS} heat

  # Add the admin role to the heat user:
  echo
  echo "** Adding the admin role to the heat user and service project..."
  echo

  openstack role add --project service --user heat admin

  # Create the heat and heat-cfn service entities:
  echo
  echo "** Creating the heat and heat-cfn service entities..."
  echo

  openstack service create --name heat \
    --description "Orchestration" orchestration
  
  openstack service create --name heat-cfn \
    --description "Orchestration"  cloudformation

  # Create the Orchestration service API endpoints:
  echo
  echo "** Creating the Orchestration service API endpoints..."
  echo

  openstack endpoint create --region RegionOne \
  orchestration public http://${controller}:8004/v1/%\(tenant_id\)s

  openstack endpoint create --region RegionOne \
  orchestration internal http://${controller}:8004/v1/%\(tenant_id\)s
  
  openstack endpoint create --region RegionOne \
  orchestration admin http://${controller}:8004/v1/%\(tenant_id\)s
  
  openstack endpoint create --region RegionOne \
  cloudformation public http://${controller}:8000/v1
  
  openstack endpoint create --region RegionOne \
  cloudformation admin http://${controller}:8000/v1
  
  
  # Orchestration requires additional information in the Identity service to manage stacks. 
  # To add this information, complete these steps:
  
  # Create the heat domain that contains projects and users for stacks:
  echo
  echo "** Creating heat domain..."
  echo
  openstack domain create --description "Stack projects and users" heat
  
  echo
  echo "** openstack service list"
  echo

  # Create the heat_domain_admin user to manage projects and users in the heat domain:
  echo
  echo "** Creating heat domain domain user..."
  echo
  openstack user create --domain heat --password ${HEAT_DOMAIN_PASS} heat_domain_admin
  
  # Add the admin role to the heat_domain_admin user in the heat domain to enable administrative 
  # stack management privileges by the heat_domain_admin user:
  echo
  echo "** Add the admin role to the heat_domain_admin user in the heat domain"
  echo
  
  openstack role add --domain heat --user-domain heat --user heat_domain_admin admin
  
  # Create the heat_stack_owner role:
  echo
  echo "** Creating the heat_stack_owner role..."
  echo
  
  openstack role create heat_stack_owner
  
  # Add the heat_stack_owner role to the demo project and user to enable stack management by the demo user:
  echo
  echo "** Add the heat_stack_owner role to the demo project and user"
  echo
  
  openstack role add --project demo --user demo heat_stack_owner
  
  # Create the heat_stack_user role:
  echo
  echo "** Creating the heat_stack_user role..."
  echo
  
  openstack role create heat_stack_user
}

install_components () {

  # Install the packages
  echo
  echo "** Installing the packages..."
  echo

  yum install openstack-heat-api openstack-heat-api-cfn \
  openstack-heat-engine -y

  # Edit the /etc/heat/heat.conf file and complete the following actions:
  CONF=/etc/heat/heat.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  # In the [database] section, configure database access:
  openstack-config --set ${CONF} database connection mysql+pymysql://heat:${HEAT_DBPASS}@${controller}/heat

  # In the [DEFAULT] and [oslo_messaging_rabbit] sections, configure RabbitMQ message queue access:
  openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_host ${controller}
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_userid openstack
  openstack-config --set ${CONF} oslo_messaging_rabbit rabbit_password ${RABBIT_PASS}

  # In the [keystone_authtoken], [trustee], [clients_keystone], and [ec2authtoken] sections,
  # configure Identity service access:
  openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
  openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
  openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
  openstack-config --set ${CONF} keystone_authtoken auth_type password
  openstack-config --set ${CONF} keystone_authtoken project_domain_name default
  openstack-config --set ${CONF} keystone_authtoken user_domain_name default
  openstack-config --set ${CONF} keystone_authtoken project_name service
  openstack-config --set ${CONF} keystone_authtoken username heat
  openstack-config --set ${CONF} keystone_authtoken password ${HEAT_PASS}

  openstack-config --set ${CONF} trustee auth_plugin password
  openstack-config --set ${CONF} trustee auth_url http://${controller}:35357
  openstack-config --set ${CONF} trustee username heat
  openstack-config --set ${CONF} trustee password ${HEAT_PASS}
  openstack-config --set ${CONF} trustee user_domain_name default

  openstack-config --set ${CONF} clients_keystone auth_uri http://${controller}:35357
  openstack-config --set ${CONF} ec2authtoken auth_uri http://${controller}:5000

  # In the [DEFAULT] section, configure the metadata and wait condition URLs:
  openstack-config --set ${CONF} DEFAULT stack_domain_admin heat_domain_admin
  openstack-config --set ${CONF} DEFAULT stack_domain_admin_password ${HEAT_DOMAIN_PASS}
  openstack-config --set ${CONF} DEFAULT stack_user_domain_name heat
  
  # Populate the Orchestration database:
  
  su -s /bin/sh -c "heat-manage db_sync" heat
}


finalize_installation () {

  # Start the Orchestration services and configure them to start when the system boots:

  echo
  echo "** starting heat service..."
  echo

  systemctl enable openstack-heat-api.service \
  openstack-heat-api-cfn.service openstack-heat-engine.service
  
  systemctl start openstack-heat-api.service \
  openstack-heat-api-cfn.service openstack-heat-engine.service

  systemctl status openstack-heat-api.service \
  openstack-heat-api-cfn.service openstack-heat-engine.service


}

#main
prerequisites
install_components
finalize_installation

echo
echo "Done."
