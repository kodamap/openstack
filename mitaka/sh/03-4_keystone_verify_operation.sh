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
# Edit the /usr/share/keystone/keystone-dist-paste.ini file and remove admin_token_auth
# from the [pipeline:public_api], [pipeline:admin_api], and [pipeline:api_v3] sections.
# CONF=/usr/share/keystone/keystone-dist-paste.ini
CONF=/etc/keystone/keystone-paste.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

sed -i 's/\ admin_token_auth\ /\ /g' ${CONF}


# Unset the temporary OS_TOKEN and OS_URL environment variables:
unset OS_TOKEN OS_URL

# The Identity version 3 API adds support for domains that contain projects and users.
# Projects and users can use the same names in different domains.
# Therefore, in order to use the version 3 API, requests must also explicitly contain at
# least the default domain or use IDs.
# For simplicity, this guide explicitly uses the default domain so examples can use names
# instead of IDs
echo
echo "** As the admin user, Request an authentication token from the Identity version 3.0 API..."
echo

openstack --os-auth-url http://${controller}:35357/v3 \
 --os-project-domain-name default --os-user-domain-name default \
 --os-project-name admin --os-username admin --os-password ${ADMIN_PASS} token issue

# As the demo user, request an authentication token from the Identity version 3 API:
echo
echo "** As the demo user, request an authentication token from the Identity version 3 API..."
echo

openstack --os-auth-url http://${controller}:5000/v3 \
 --os-project-domain-name default --os-user-domain-name default \
 --os-project-name demo --os-username demo --os-password ${DEMO_PASS} token issue

echo
echo "Done."
