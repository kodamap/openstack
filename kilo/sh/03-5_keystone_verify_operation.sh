#!/bin/sh

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <Controller IP>"
    exit 0
fi

controller=$1

# For security reasons, disable the temporary authentication token mechanism:
#
# Edit the /usr/share/keystone/keystone-dist-paste.ini file and remove admin_token_auth
# from the [pipeline:public_api], [pipeline:admin_api], and [pipeline:api_v3] sections.
CONF=/usr/share/keystone/keystone-dist-paste.ini
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

sed -i 's/\ admin_token_auth\ /\ /g' ${CONF}


# Unset the temporary OS_TOKEN and OS_URL environment variables:
unset OS_TOKEN OS_URL

# As the admin user, request an authentication token from the Identity version 2.0 API:
echo
echo "** As the admin user, Request an authentication token from the Identity version 2.0 API..."
echo

openstack --os-auth-url http://${controller}:35357 \
  --os-project-name admin --os-username admin --os-auth-type password \
  token issue
  
# The Identity version 3 API adds support for domains that contain projects and users. 
# Projects and users can use the same names in different domains. 
# Therefore, in order to use the version 3 API, requests must also explicitly contain at
# least the default domain or use IDs. 
# For simplicity, this guide explicitly uses the default domain so examples can use names
# instead of IDs
echo
echo "** As the admin user, Request an authentication token from the Identity version 3.0 API..."
echo

openstack --os-auth-url http://${controller}:35357 \
  --os-project-domain-id default --os-user-domain-id default \
  --os-project-name admin --os-username admin --os-auth-type password \
  token issue
  
# As the admin user, list projects to verify that the admin user can execute admin-only 
# CLI commands and that the Identity service contains the projects that you created in the
# section called “Create projects, users, and roles”:
echo
echo "** As the admin user, list projects..."
echo

openstack --os-auth-url http://${controller}:35357 \
  --os-project-name admin --os-username admin --os-auth-type password \
  project list
  
# As the admin user, list users to verify that the Identity service contains the users
# that you created in the section called “Create projects, users, and roles”:
echo
echo "** As the admin user, list users..."
echo

openstack --os-auth-url http://${controller}:35357 \
  --os-project-name admin --os-username admin --os-auth-type password \
  user list


# As the admin user, list roles to verify that the Identity service contains the role
# that you created in the section called “Create projects, users, and roles”:
echo
echo "** As the admin user, list role..."
echo

openstack --os-auth-url http://${controller}:35357 \
  --os-project-name admin --os-username admin --os-auth-type password \
  role list

# As the demo user, request an authentication token from the Identity version 3 API:
echo
echo "** As the demo user, request an authentication token from the Identity version 3 API..."
echo

openstack --os-auth-url http://${controller}:5000 \
  --os-project-domain-id default --os-user-domain-id default \
  --os-project-name demo --os-username demo --os-auth-type password \
  token issue

# As the demo user, attempt to list users to verify that it cannot execute admin-only 
# CLI commands:
echo
echo "** ** LAST Verify ** As the demo user, list users... will be failed"
echo "** Expect respone : (HTTP 403)"
echo

openstack --os-auth-url http://${controller}:5000 \
  --os-project-domain-id default --os-user-domain-id default \
  --os-project-name demo --os-username demo --os-auth-type password \
  user list

echo
echo "Done."
