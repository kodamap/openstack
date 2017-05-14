#!/bin/sh -e

export LANG=en_US.utf8

SH=basic_environment.sh

function basic_env_other_nodes {

    cat <<'EOF' > ../lib//${SH}
#!/bin/sh -e

export LANG=en_US.utf8
timedatectl set-timezone Asia/Tokyo

echo "** ----------------------------------------------------------------"
echo "** Started the $0 on `hostname`"
echo "** ----------------------------------------------------------------"

controller=$1

# Disable firewall
echo
echo "** Disabling firewalld..."
echo

yum -y install firewalld
systemctl stop firewalld
systemctl disable firewalld

# To install the NTP service
echo
echo "** Installing the packages"
echo

yum -y -q install ntp
yum -y -q install git

# To configure the NTP service
CONF=/etc/ntp.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

if grep "server ${controller} iburst" ${CONF} > /dev/null ; then
   cp -pf ${CONF}.org ${CONF}
fi

sed -i "/^server 3.centos.pool.ntp.org iburst$/a server ${controller} iburst" ${CONF}
sed -i '/^server 0.centos.pool.ntp.org iburst/s/^/#/' ${CONF}
sed -i '/^server 1.centos.pool.ntp.org iburst/s/^/#/' ${CONF}
sed -i '/^server 2.centos.pool.ntp.org iburst/s/^/#/' ${CONF}
sed -i '/^server 3.centos.pool.ntp.org iburst/s/^/#/' ${CONF}

systemctl enable ntpd.service
systemctl start ntpd.service

echo
echo "** Configured and Started the NTP service."
echo

echo
echo "** ntpq -c peers"
echo

ntpq -c peers

echo
echo "** ntpq -c assoc"
echo

ntpq -c assoc

# To configure prerequisites
# On RHEL and CentOS, enable the EPEL repository:
if [ ! -f /etc/yum.repos.d/epel.repo ] ; then
    yum -y -q install http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
fi

# To enable the OpenStack repository
# Install the rdo-release-kilo package to enable the RDO repository:
if [ ! -f /etc/yum.repos.d/rdo-release.repo ] ; then
   yum -y -q install http://rdo.fedorapeople.org/openstack-kilo/rdo-release-kilo.rpm
fi

# To finalize installation
# Upgrade the packages on your system:
echo
echo "** upgrading your system....this will take few more minutes"
echo

yum -y -q upgrade

echo
echo "** upgrading done."
echo

# RHEL and CentOS enable SELinux by default. Install the openstack-selinux package to
# automatically manage security policies for OpenStack services:
echo
echo "** installing openstack-selinux..."
echo

yum -y -q install openstack-selinux

# To install openstack-config
yum -y -q install openstack-utils

echo "** ----------------------------------------------------------------"
echo "** Complete the $0 on `hostname`"
echo "** ----------------------------------------------------------------"
EOF
}


# main

if [ $# -ne 2 ]; then
    echo "** Usage: $0 <controller node IP> <other node ip>"
    exit 1
fi

controller=$1
other_node=$2

ssh-copy-id root@${other_node}
basic_env_other_nodes
chmod 755 ../lib//${SH}
scp -p ../lib//${SH} root@${other_node}:/root/
ssh root@${other_node} "/root/${SH} ${controller}"

echo
echo "** Done."
