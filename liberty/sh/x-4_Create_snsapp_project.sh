#!/bin/sh -e

# this scripts is origined from quickrdo

export LANG=en_US.utf8

source /root/admin-openrc

echo
echo "** Configuration(SNSApp) started."
echo

#
# create project and users
#
openstack user show snsapp-infra-admin && openstack user delete snsapp-infra-admin
openstack user show snsapp-infra-user && openstack user delete snsapp-infra-user
openstack project show SNSApp && openstack project delete SNSApp

openstack project create --description "SNSApp Project" SNSApp
openstack user create --password password snsapp-infra-admin
openstack user create --password password snsapp-infra-user
openstack role add --project SNSApp --user snsapp-infra-admin admin
openstack role add --project SNSApp --user snsapp-infra-user user

#
# setup flavor
#
openstack flavor show standard.xsmall && openstack flavor delete standard.xsmall
openstack flavor show standard.small && openstack flavor delete standard.small
openstack flavor show standard.medium && openstack flavor delete standard.medium

nova flavor-create --ephemeral 10 --rxtx-factor 1.0 standard.xsmall 100 1024 10 1
nova flavor-create --ephemeral 10 --rxtx-factor 1.0 standard.small  101 2048 10 2
nova flavor-create --ephemeral 50 --rxtx-factor 1.0 standard.medium 102 4096 50 2
nova flavor-access-add 100 SNSApp
nova flavor-access-add 101 SNSApp
nova flavor-access-add 102 SNSApp

tenant=$(openstack project list | awk '/ SNSApp / {print $2}')
nova quota-update --instances 20 $tenant
nova quota-update --cores 40 $tenant
nova quota-update --security-groups 20 $tenant
nova quota-update --security-group-rules 40 $tenant



echo
echo "** Configuration finished."
echo