#!/bin/sh -e

export LANG=en_US.utf8

# To Fix it , Modify the paramters manually.

SH=install_and_configure_ceilometer.sh
PW_FILE=OPENSTACK_PASSWD.ini

function generate_ceilometer_sh {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

if [ $# -ne 1 ]; then
    echo "** Usage: $0 <controller ip>"
    exit 1
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
CEILOMETER_DBPASS=`get_passwd CEILOMETER_DBPASS`
CEILOMETER_PASS=`get_passwd CEILOMETER_PASS`
RABBIT_PASS=`get_passwd RABBIT_PASS`

# Configure Cinder to use Telemetry on Block storage node.
# Edit the /etc/cinder/cinder.conf file and complete the following actions:
CONF=/etc/cinder/cinder.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [oslo_messaging_notifications] section, configure notifications:
openstack-config --set ${CONF} oslo_messaging_notifications driver messagingv2

# To finalize the installation

# Restart the Block Storage services on the storage nodes:
echo
echo "** Restarting cinder service on block storage node..."
echo

systemctl restart openstack-cinder-volume.service
systemctl status openstack-cinder-volume.service

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}

# main


if [ $# -ne 2 ]; then
    echo "** Usage: $0 <controller node ip> <compute ip>"
    exit 1
fi

controller=$1
compute=$2

ssh-copy-id root@${compute}
generate_ceilometer_sh
chmod 755 ../lib//${SH}
scp -p ${PW_FILE} root@${compute}:/root/
scp -p ../lib//${SH} root@${compute}:/root/
ssh root@${compute} "/root/${SH} ${controller}"

# Configure Cinder to use Telemetry on Contoller node.
# Edit the /etc/cinder/cinder.conf file and complete the following actions:
CONF=/etc/cinder/cinder.conf
echo
echo "** Editing ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

# In the [oslo_messaging_notifications] section, configure notifications:
openstack-config --set ${CONF} oslo_messaging_notifications driver messagingv2

# Restart the Block Storage services on the controller node:
echo
echo "** Starting cinder service service on controller node..."
echo

systemctl restart openstack-cinder-api.service openstack-cinder-scheduler.service
systemctl status openstack-cinder-api.service openstack-cinder-scheduler.service


# Use the cinder-volume-usage-audit command on Block Storage nodes
# to retrieve meters on demand

echo
echo "Done."
