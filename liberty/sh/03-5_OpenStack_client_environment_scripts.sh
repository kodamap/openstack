#!/bin/sh

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <Controller IP>"
    exit 1
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
ADMIN_PASS=`get_passwd ADMIN_PASS`
DEMO_PASS=`get_passwd DEMO_PASS`

echo
echo "Creating admin-openrc."
echo

cat << EOF > ~/admin-openrc
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=admin
export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_AUTH_URL=http://${controller}:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export PS1='[\u@\h \W(admin)]\\\$ '
EOF

echo
echo "** ~/admin-openrc"
cat ~/admin-openrc
echo

echo
echo "Creating demo-openrc."
echo

cat << EOF > ~/demo-openrc
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=${DEMO_PASS}
export OS_AUTH_URL=http://${controller}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export PS1='[\u@\h \W(demo)]\\\$ '
EOF

echo
echo "** ~/demo-openrc"
cat ~/demo-openrc
echo

echo
echo "Load the admin-openrc.sh file to populate environment variables with the location of the Identity service and the admin project and user credentials:"
echo

. ~/demo-openrc

echo
echo "openstack token issue"
echo

openstack token issue

echo
echo "Done."

