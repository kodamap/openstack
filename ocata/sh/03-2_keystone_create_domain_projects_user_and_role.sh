#!/bin/sh -e

export LANG=en_US.utf8

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
ADMIN_PASS=`get_passwd ADMIN_PASS`
DEMO_PASS=`get_passwd DEMO_PASS`


if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

create_domain_projects_users () {

  # Configure the authentication token:
  export OS_USERNAME=admin
  export OS_PASSWORD=${ADMIN_PASS}
  export OS_PROJECT_NAME=admin
  export OS_USER_DOMAIN_NAME=Default
  export OS_PROJECT_DOMAIN_NAME=Default
  export OS_AUTH_URL=http://${controller}:35357/v3
  export OS_IDENTITY_API_VERSION=3
  
  # Create the service project:
  echo
  echo "** Creating the service project..."
  echo

  openstack project create --domain default --description "Service Project" service

  # Create the demo project:
  echo
  echo "** Creating demo project..."
  echo

  openstack project create --domain default  --description "Demo Project" demo

  # Create the demo user:
  echo
  echo "** Creating the demo user..."
  echo

  openstack user create --domain default --password ${DEMO_PASS} demo

  # Create the user role:
  echo
  echo "** Creating the user role..."
  echo

  openstack role create user

  # Add the user role to the demo project and user:
  echo
  echo "** Adding the user role to the demo project and user..."
  echo

  openstack role add --project demo --user demo user
  
}

# main
create_domain_projects_users

# verify operation
echo
echo "** openstack service list"
echo

openstack service list

echo
echo "** Done."
echo
