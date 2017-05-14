#!/bin/sh -e

export LANG=en_US.utf8

# main

if [ $# -ne 1 ]; then
    echo "** Usage: $0 <object node ip>"
    exit 0
fi

object=$1

PW_FILE=OPENSTACK_PASSWD.ini

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix it , Modify the paramters manually.
HASH_PATH_SUFFIX=`get_passwd HASH_PATH_SUFFIX`
HASH_PATH_PREFIX=`get_passwd HASH_PATH_PREFIX`

# Obtain the /etc/swift/swift.conf file from the Object Storage source repository:

curl -o /etc/swift/swift.conf \
  https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/kilo

# Edit the /etc/swift/swift.conf file and complete the following actions:
# In the [swift-hash] section, configure the hash path prefix and suffix for your environment.
CONF=/etc/swift/swift.conf
echo
echo "** Editting ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

openstack-config --set ${CONF} swift-hash swift_hash_path_suffix ${HASH_PATH_SUFFIX}
openstack-config --set ${CONF} swift-hash swift_hash_path_prefix ${HASH_PATH_PREFIX}

# In the [storage-policy:0] section, configure the default storage policy:
openstack-config --set ${CONF} storage-policy:0 name Policy-0
openstack-config --set ${CONF} storage-policy:0 default yes

# Copy the swift.conf file to the /etc/swift directory on each storage node and any additional
# nodes running the proxy service.
scp /etc/swift/swift.conf root@${object}:/etc/swift/

# On all nodes, ensure proper ownership of the configuration directory:
ssh root@${object} "chown -R swift:swift /etc/swift"

# On the controller node and any other nodes running the proxy service, start the Object Storage proxy service
# including its dependencies and configure them to start when the system boots:
echo
echo "** Enabling and Starting openstack-swift-proxy.service  memcached.service..."
echo

systemctl enable openstack-swift-proxy.service memcached.service
systemctl start openstack-swift-proxy.service memcached.service
systemctl status openstack-swift-proxy.service memcached.service | grep -B 3 Active:

#ssh root@${object} "systemctl enable openstack-swift-proxy.service memcached.service"
#ssh root@${object} "systemctl start openstack-swift-proxy.service memcached.service"
#ssh root@${object} "systemctl status openstack-swift-proxy.service memcached.service | grep -B 3 Active:"

# On the storage nodes, start the Object Storage services and configure them to start when the system boots:
echo
echo "** Enabling and Starting swift services on ${object}..."
echo

ssh root@${object} "systemctl enable openstack-swift-account.service openstack-swift-account-auditor.service openstack-swift-account-reaper.service openstack-swift-account-replicator.service"
ssh root@${object} "systemctl enable openstack-swift-container.service openstack-swift-container-auditor.service openstack-swift-container-replicator.service openstack-swift-container-updater.service"
ssh root@${object} "systemctl enable openstack-swift-object.service openstack-swift-object-auditor.service openstack-swift-object-replicator.service openstack-swift-object-updater.service"
ssh root@${object} "systemctl start openstack-swift-account.service openstack-swift-account-auditor.service openstack-swift-account-reaper.service openstack-swift-account-replicator.service"
ssh root@${object} "systemctl start openstack-swift-container.service openstack-swift-container-auditor.service openstack-swift-container-replicator.service openstack-swift-container-updater.service"
ssh root@${object} "systemctl start openstack-swift-object.service openstack-swift-object-auditor.service openstack-swift-object-replicator.service openstack-swift-object-updater.service"
ssh root@${object} "systemctl status openstack-swift-account.service openstack-swift-account-auditor.service openstack-swift-account-reaper.service openstack-swift-account-replicator.service | grep -B 3 Active:"
ssh root@${object} "systemctl status openstack-swift-container.service openstack-swift-container-auditor.service openstack-swift-container-replicator.service openstack-swift-container-updater.service | grep -B 3 Active:"
ssh root@${object} "systemctl status openstack-swift-object.service openstack-swift-object-auditor.service openstack-swift-object-replicator.service openstack-swift-object-updater.service | grep -B 3 Active:"

# Verify operation
# ource the demo credentials:

echo
echo "** Verify operation started."
echo

source ~/demo-openrc

# Show the service status:
echo
echo "** swift -V 3 stat"
echo

swift -V 3 stat
sleep 1;

# Upload a test file:
echo
echo "** Upload a test file"
echo

echo test > test.txt

swift -V 3 upload demo-container1 test.txt
sleep 1;

# List containers
echo
echo "** swift -V 3 list"
echo

swift -V 3 list
sleep 1;

# Download a test file:
echo
echo "** swift -V 3 download demo-container1 test.txt"
echo

swift -V 3 download demo-container1 test.txt
cat test.txt

echo
echo "Done."
echo
