#!/bin/sh -e

# Prerequisite
# - Install the supporting utility packages
# yum install xfsprogs rsync -y
#
# - Copy the contents of the /etc/hosts file from the controller node and add the following to it:
# - Install and configure NTP using the instructions
# - Format the /dev/sdx1 and /dev/sdx1 partitions as XFS:
#   ex) mkfs.xfs /dev/sdc -f
#       mkfs.xfs /dev/sdd -f
#       mkdir -p /srv/node/sdc
#       mkdir -p /srv/node/sdd
# Edit the /etc/fstab file and add the following to it:
#      /dev/sdc /srv/node/sdc xfs noatime,nodiratime,nobarrier,logbufs=8 0 2
#      /dev/sdd /srv/node/sdd xfs noatime,nodiratime,nobarrier,logbufs=8 0 2
# Mount the devices:
#       mount /dev/sdc /srv/node/sdc
#       mount /dev/sdd /srv/node/sdd

export LANG=en_US.utf8

function generate_swift_sh {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

storage=$1

# Prepare for swift
mkfs.xfs /dev/vdc -f
mkfs.xfs /dev/vdd -f
mkdir -p /srv/node/vdc
mkdir -p /srv/node/vdd

CONF=/etc/fstab
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

echo "/dev/vdc /srv/node/vdc xfs noatime,nodiratime,nobarrier,logbufs=8 0 2
/dev/vdd /srv/node/vdd xfs noatime,nodiratime,nobarrier,logbufs=8 0 2
" >> ${CONF}
mount -a 
df -h ; sleep 1

# Install the packages:

echo
echo "** Installing the packages..."
echo

# Install the supporting utility packages:

yum -y install xfsprogs rsync

# Edit the /etc/rsyncd.conf file and add the following to it:
CONF=/etc/rsyncd.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

echo "uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = ${storage}

[account]
max connections = 2
path = /srv/node/
read only = false
lock file = /var/lock/account.lock

[container]
max connections = 2
path = /srv/node/
read only = false
lock file = /var/lock/container.lock

[object]
max connections = 2
path = /srv/node/
read only = false
lock file = /var/lock/object.lock
" >> ${CONF}

# Start the rsyncd service and configure it to start when the system boots:
echo
echo "** Starting rsyncd..."
echo

systemctl enable rsyncd.service
systemctl start rsyncd.service
systemctl status rsyncd.service

# Install and configure storage node components
# Install the packages:
echo
echo "** Installing the packages..."
echo

yum -y install openstack-swift-account openstack-swift-container openstack-swift-object

# Obtain the accounting, container, object, container-reconciler,
# and object-expirer service configuration files from the Object Storage source repository:
echo
echo "** Downloading swift config..."
echo

curl -o /etc/swift/account-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?h=stable/liberty
curl -o /etc/swift/container-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/liberty
curl -o /etc/swift/object-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/liberty

# Edit the /etc/swift/account-server.conf file and complete the following actions:
CONF=/etc/swift/account-server.conf
echo
echo "** Editting ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [DEFAULT] section, configure the bind IP address, bind port, user, configuration directory, and mount point directory:openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
openstack-config --set ${CONF} DEFAULT bind_ip ${storage}
openstack-config --set ${CONF} DEFAULT bind_port 6002
openstack-config --set ${CONF} DEFAULT user swift
openstack-config --set ${CONF} DEFAULT swift_dir /etc/swift
openstack-config --set ${CONF} DEFAULT devices /srv/node
openstack-config --set ${CONF} DEFAULT mount_check true

# In the [pipeline:main] section, enable the appropriate modules:
openstack-config --set ${CONF} pipeline:main pipeline "healthcheck recon account-server"

# In the [filter:recon] section, configure the recon (metrics) cache directory:
openstack-config --set ${CONF} filter:recon use egg:swift#recon
openstack-config --set ${CONF} filter:recon recon_cache_path /var/cache/swift

# Edit the /etc/swift/container-server.conf file and complete the following actions:
CONF=/etc/swift/container-server.conf
echo
echo "** Editting ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [DEFAULT] section, configure the bind IP address, bind port, user, configuration directory, and mount point directory:openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
openstack-config --set ${CONF} DEFAULT bind_ip ${storage}
openstack-config --set ${CONF} DEFAULT bind_port 6001
openstack-config --set ${CONF} DEFAULT user swift
openstack-config --set ${CONF} DEFAULT swift_dir /etc/swift
openstack-config --set ${CONF} DEFAULT devices /srv/node
openstack-config --set ${CONF} DEFAULT mount_check true

# In the [pipeline:main] section, enable the appropriate modules:
openstack-config --set ${CONF} pipeline:main pipeline "healthcheck recon container-server"

# In the [filter:recon] section, configure the recon (metrics) cache directory:
openstack-config --set ${CONF} filter:recon use egg:swift#recon
openstack-config --set ${CONF} filter:recon recon_cache_path /var/cache/swift

# Edit the /etc/swift/object-server.conf file and complete the following actions:
CONF=/etc/swift/object-server.conf
echo
echo "** Editting ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [DEFAULT] section, configure the bind IP address, bind port, user, configuration directory, and mount point directory:openstack-config --set ${CONF} DEFAULT rpc_backend rabbit
openstack-config --set ${CONF} DEFAULT bind_ip ${storage}
openstack-config --set ${CONF} DEFAULT bind_port 6000
openstack-config --set ${CONF} DEFAULT user swift
openstack-config --set ${CONF} DEFAULT swift_dir /etc/swift
openstack-config --set ${CONF} DEFAULT devices /srv/node
openstack-config --set ${CONF} DEFAULT mount_check true


# In the [pipeline:main] section, enable the appropriate modules:
openstack-config --set ${CONF} pipeline:main pipeline "healthcheck recon object-server"

# In the [filter:recon] section, configure the recon (metrics) cache directory:
openstack-config --set ${CONF} filter:recon use egg:swift#recon
openstack-config --set ${CONF} filter:recon recon_cache_path /var/cache/swift
openstack-config --set ${CONF} filter:recon recon_lock_path /var/lock

# Ensure proper ownership of the mount point directory structure:
chown -R swift:swift /srv/node

# Create the recon directory and ensure proper ownership of it:
mkdir -p /var/cache/swift
chown -R swift:swift /var/cache/swift

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main

if [ $# -ne 1 ]; then
    echo "** Usage: $0 <storage node ip>"
    exit 0
fi

storage=$1

SH=install_and_configure_swift.sh
PW_FILE=OPENSTACK_PASSWD.ini

ssh-copy-id root@${storage}
generate_swift_sh
chmod 755 ../lib//${SH}
scp -p ../lib//${SH} root@${storage}:/root/
scp -p ${PW_FILE} root@${storage}:/root/
ssh root@${storage} "/root/${SH} ${storage}"

echo
echo "Done."
