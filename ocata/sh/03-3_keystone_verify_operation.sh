#!/bin/sh

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <Controller IP>"
    exit 0
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
ADMIN_PASS=`get_passwd ADMIN_PASS`
DEMO_PASS=`get_passwd DEMO_PASS`

# For security reasons, disable the temporary authentication token mechanism:
#
# Edit the /etc/keystone/keystone-paste.ini file and remove admin_token_auth 
# from the [pipeline:public_api], [pipeline:admin_api], and [pipeline:api_v3] sections.
CONF=/etc/keystone/keystone-paste.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

sed -i 's/\ admin_token_auth\ /\ /g' ${CONF}


# Unset the temporary OS_AUTH_URL and OS_PASSWORD environment variable:
unset OS_AUTH_URL OS_PASSWORD

# As the admin user, request an authentication token:
echo
echo "** As the admin user, request an authentication token:..."
echo

export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${controller}:35357/v3
export OS_IDENTITY_API_VERSION=3

openstack --os-auth-url http://${controller}:35357/v3 \
  --os-project-domain-name default --os-user-domain-name default \
  --os-project-name admin --os-username admin token issue

# As the demo user, request an authentication token:
echo
echo "** As the demo user, request an authentication token:..."
echo

unset OS_AUTH_URL OS_PASSWORD

export OS_USERNAME=admin
export OS_PASSWORD=${DEMO_PASS}
export OS_PROJECT_NAME=demo
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${controller}:35357/v3
export OS_IDENTITY_API_VERSION=3

openstack --os-auth-url http://${controller}:5000/v3 \
 --os-project-domain-name default --os-user-domain-name default \
 --os-project-name demo --os-username demo token issue

echo
echo "Done."
