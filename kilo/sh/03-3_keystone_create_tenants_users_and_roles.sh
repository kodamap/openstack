#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

# Configure the authentication token:
export OS_TOKEN=`grep ^admin_token /etc/keystone/keystone.conf |awk -F= '{print $2}' | sed -e 's/ //g'`

# Configure the endpoint URL:
export OS_URL=http://${controller}:35357/v2.0

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
ADMIN_PASS=`get_passwd ADMIN_PASS`
DEMO_PASS=`get_passwd DEMO_PASS`

# To create tenants, users, and roles
# Create an administrative project, user, and role for administrative operations in your environment:
# Create the admin project:
#
echo
echo "** Creatging - admin - Project ..."
echo

openstack project create --description "Admin Project" admin

# Create the admin user:
echo
echo "** Creating the admin user..."
echo

openstack user create --password ${ADMIN_PASS} admin

# Create the admin role:
echo
echo "** Creating the admin role..."
echo

openstack role create admin

# Add the admin role to the admin project and user:
# Note : Any roles that you create must map to roles specified in the policy.json file in the configuration
# file directory of each OpenStack service.
# The default policy for most services grants administrative access to the admin role.
# For more information, see the Operations Guide - Managing Projects and Users.
echo
echo "** Adding the admin role to the admin project and user..."
echo

openstack role add --project admin --user admin admin

# Create the service project:
echo
echo "** Creating the service project..."
echo

openstack project create --description "Service Project" service

# Create the demo project:
echo
echo "** Creating demo project..."
echo

openstack project create --description "Demo Project" demo

# Create the demo user:
echo
echo "** Creating the demo user..."
echo

openstack user create --password ${DEMO_PASS} demo

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

echo
echo "** Done."