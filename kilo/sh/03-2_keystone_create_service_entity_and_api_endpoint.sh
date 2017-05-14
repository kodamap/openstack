#!/bin/sh -e

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

# To configure prerequisites
echo
echo "** Create the service entity and API endpoint..."
echo

# Configure the authentication token:
export OS_TOKEN=`grep ^admin_token /etc/keystone/keystone.conf |awk -F= '{print $2}' | sed -e 's/ //g'`

# Configure the endpoint URL:
export OS_URL=http://${controller}:35357/v2.0

# To create the service entity and API endpoint
# The Identity service manages a catalog of services in your OpenStack environment.
# Services use this catalog to determine the other services available in your environment.
#
# Create the service entity for the Identity service:
openstack service create \
--name keystone --description "OpenStack Identity" identity

# The Identity service manages a catalog of API endpoints associated with the services in your
# OpenStack environment.
# Services use this catalog to determine how to communicate with other services in your environment.
#
# OpenStack uses three API endpoint variants for each service: admin, internal, and public.
# The admin API endpoint allows modifying users and tenants by default, while the public and internal
# APIs do not.
# In a production environment, the variants might reside on separate networks that service
# different types of users for security reasons.
# For instance, the public API network might be reachable from outside the cloud for management tools,
# the admin API network might be protected, while the internal API network is connected to each host.
# Also, OpenStack supports multiple regions for scalability.
# For simplicity, this guide uses the management network for all endpoint variations and the default
# RegionOne region.
#
# Note : Each service that you add to your OpenStack environment requires one or more service entities
# and one API endpoint in the Identity service.
openstack endpoint create \
  --publicurl http://${controller}:5000/v2.0 \
  --internalurl http://${controller}:5000/v2.0 \
  --adminurl http://${controller}:35357/v2.0 \
  --region RegionOne \
  identity

# verify operation
echo
echo "** openstack service list"
echo

openstack service list

echo "** Done."
