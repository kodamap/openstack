#!/bin/sh -e

# Make sure that you create a lvm volume  before you run this script
# Note : If your system uses a different device name, adjust these steps accordingly.
#
# Create the LVM physical volume
#
# pvcreate /dev/sdb
#
# Create the LVM volume group cinder-volumes:
# The Block Storage service creates logical volumes in this volume group.
#
# vgcreate cinder-volumes /dev/sdb
#
# Edit the /etc/lvm/lvm.conf file and complete the following actions:
#
# In the devices section, add a filter that accepts the /dev/sdb device and rejects all other devices:
#
# devices {
# ...
# filter = [ "a/sdb/", "r/.*/"]
#

export LANG=en_US.utf8

SH=install_and_configure_cinder.sh
PW_FILE=OPENSTACK_PASSWD.ini

function generate_cinder_sh {

    cat <<'EOF' > ../../lib/${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

controller=$1
block=$2
iscsi_ip_address=$3

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
DATABASE_PASS=`get_passwd DATABASE_PASS`
CINDER_PASS=`get_passwd CINDER_PASS`
CINDER_DBPASS=`get_passwd CINDER_DBPASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# Install the packages:

echo
echo "** Installing the packages..."
echo

# To configure prerequisites
# Enable the OpenStack repository
if [ ! -f /etc/yum.repos.d/CentOS-OpenStack-ocata.repo ] ; then
    yum install centos-release-openstack-ocata -y
fi

# RHEL and CentOS enable SELinux by default. Install the openstack-selinux package to
# automatically manage security policies for OpenStack services:
yum -y install openstack-selinux

# Install the LVM packages:
yum -y install lvm2 openstack-utils

# Start the LVM metadata service and configure it to start when the system boots:
echo
echo "** Starting lvm2 service"
systemctl enable lvm2-lvmetad.service
systemctl start lvm2-lvmetad.service
systemctl status lvm2-lvmetad.service

# Prepare for cinder
CONF=/etc/lvm/lvm.conf
echo
echo "** Editting ${CONF}..."
echo

#test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org
#pvcreate /dev/vdb --force
#vgcreate cinder-volumes /dev/vdb
#sed -i '141a \ \ \ \ \ \ \ \ filter = [ "a/vdb/", "r/.*/"]' ${CONF}

# Install and configure Block Storage volume components
yum -y install openstack-cinder targetcli python-keystone

# Edit the /etc/cinder/cinder.conf file and complete the following actions:
CONF=/etc/cinder/cinder.conf
echo
echo "** Editting ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [database] section, configure database access:
openstack-config --set ${CONF} database connection mysql+pymysql://cinder:${CINDER_DBPASS}@${controller}/cinder

# In the [DEFAULT] ,configure RabbitMQ message queue access:
#openstack-config --set ${CONF} DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${controller}
## for rdo
openstack-config --set ${CONF} DEFAULT transport_url rabbit://guest:guest@${controller}

# In the [DEFAULT] and [keystone_authtoken] sections, configure Identity service access:
# Note : Comment out or remove any other options in the [keystone_authtoken] section.
openstack-config --set ${CONF} DEFAULT auth_strategy keystone
openstack-config --set ${CONF} keystone_authtoken auth_uri http://${controller}:5000
openstack-config --set ${CONF} keystone_authtoken auth_url http://${controller}:35357
openstack-config --set ${CONF} keystone_authtoken memcached_servers ${controller}:11211
openstack-config --set ${CONF} keystone_authtoken auth_type password
openstack-config --set ${CONF} keystone_authtoken project_domain_name default
openstack-config --set ${CONF} keystone_authtoken user_domain_name default
#openstack-config --set ${CONF} keystone_authtoken project_name service
## for rdo
openstack-config --set ${CONF} keystone_authtoken project_name services
openstack-config --set ${CONF} keystone_authtoken username cinder
openstack-config --set ${CONF} keystone_authtoken password ${CINDER_PASS}
  
# In the [DEFAULT] section, configure the my_ip option to use the management interface
openstack-config --set ${CONF} DEFAULT my_ip ${block}

# In the [lvm] section, configure the LVM back end with the LVM driver, cinder-volumes volume group,
# iSCSI protocol, and appropriate iSCSI service:

openstack-config --set ${CONF} lvm volume_driver cinder.volume.drivers.lvm.LVMVolumeDriver
openstack-config --set ${CONF} lvm volume_group cinder-volumes
openstack-config --set ${CONF} lvm iscsi_protocol iscsi
openstack-config --set ${CONF} lvm iscsi_helper lioadm
openstack-config --set ${CONF} lvm iscsi_ip_address ${iscsi_ip_address}

# In the [DEFAULT] section, enable the LVM back end:
openstack-config --set ${CONF} DEFAULT enabled_backends lvm

# In the [DEFAULT] section, configure the location of the Image service:
openstack-config --set ${CONF} DEFAULT glance_api_servers  http://${controller}:9292

# In the [oslo_concurrency] section, configure the lock path:
openstack-config --set ${CONF} oslo_concurrency lock_path /var/lib/cinder/tmp

# (Optional) To assist with troubleshooting, enable verbose logging in the [DEFAULT] section:
### openstack-config --set ${CONF} DEFAULT verbose  True


# To finalize installation
# Start the Block Storage volume service including its dependencies and configure them to start
# when the system boots:
echo
echo "** Starting cinder services on `hostname`..."
echo

systemctl enable openstack-cinder-volume.service target.service
systemctl start openstack-cinder-volume.service target.service
systemctl status openstack-cinder-volume.service target.service

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main

if [ $# -ne 3 ]; then
    echo "** Usage: $0 <controller node IP> <block node ip> <iscsi_ip_address>"
    exit 0
fi

controller=$1
block=$2
iscsi_ip_address=$3

ssh-copy-id root@${block}
generate_cinder_sh
chmod 755 ../../lib/${SH}
scp -p ../../lib/${SH} root@${block}:/root/
scp -p ${PW_FILE} root@${block}:/root/
ssh root@${block} "/root/${SH} ${controller} ${block} ${iscsi_ip_address}"

# Verify operation
# Source the admin credentials to gain access to admin-only CLI commands:
source ~/admin-openrc

# List service components to verify successful launch of each process:
echo
echo "** openstack volume service list"
echo

sleep 3;

openstack volume service list

echo
echo "Done."
