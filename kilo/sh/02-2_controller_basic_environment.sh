#!/bin/sh -e

export LANG=en_US.utf8
timedatectl set-timezone Asia/Tokyo

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini
function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# To Fix the password , Edit these paramters manually.
DATABASE_PASS=`grep ^DATABASE_PASS OPENSTACK_PASSWD.ini | awk -F= '{print $2}' | sed 's/ //g'`
RABBIT_PASS=`grep ^RABBIT_PASS OPENSTACK_PASSWD.ini | awk -F= '{print $2}' | sed 's/ //g'`

# Disable firewall
echo
echo "** Disabling firewalld..."
echo

yum -y install firewalld
systemctl stop firewalld
systemctl disable firewalld

# To generate ssh-key
echo
echo "** Generating ssh key-pair..."
echo

ssh-keygen -t rsa -N ""

# To install the NTP service
echo
echo "** Installing ntp packages."
echo

yum -y -q install ntp

# To configure the NTP service
CONF=/etc/ntp.conf
echo
echo "** Editing the ${CONF}..."
echo

test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

if grep "restrict -4 default kod notrap nomodify" ${CONF} > /dev/null ; then
   cp -pf ${CONF}.org ${CONF}
fi

sed -i "/^server 3.centos.pool.ntp.org iburst$/a restrict -6 default kod notrap nomodify" ${CONF}
sed -i "/^server 3.centos.pool.ntp.org iburst$/a restrict -4 default kod notrap nomodify" ${CONF}

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


echo
echo "** Enable EPEL/OpenStack Repository..."
echo

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
echo "** upgrading your system....this will take a few more minutes"
echo

yum -y -q upgrade

echo
echo "** upgrading done."
echo

echo
echo "** Installing packages..."
echo

# RHEL and CentOS enable SELinux by default. Install the openstack-selinux package to
# automatically manage security policies for OpenStack services:
yum -y -q install openstack-selinux

# To install and configure the database server
yum -y -q install mariadb mariadb-server MySQL-python

# To install openstack-config
yum -y -q install openstack-utils

# Create and edit the /etc/my.cnf.d/mariadb_openstack.cnf file from /etc/my.cnf.d/server.cnf
CONF=/etc/my.cnf.d/mariadb_openstack.cnf
cp -p /etc/my.cnf.d/server.cnf ${CONF}

# In the [mysqld] section, set the bind-address key to the management IP address of
# the controller node to enable access by other nodes via the management network:
sed -i "/^\[mysqld\]$/a bind-address = ${controller}" ${CONF}

# In the [mysqld] section, set the following keys to enable useful options and the UTF-8 character set:
if grep "default-storage-engine = innodb" ${CONF} > /dev/null ; then
   cp -pf /etc/my.cnf.d/server.cnf ${CONF}
fi

sed -i "/^\[mysqld\]$/a default-storage-engine = innodb" ${CONF}
sed -i "/^\[mysqld\]$/a innodb_file_per_table" ${CONF}
sed -i "/^\[mysqld\]$/a collation-server = utf8_general_ci" ${CONF}
sed -i "/^\[mysqld\]$/a init-connect = 'SET NAMES utf8'" ${CONF}
sed -i "/^\[mysqld\]$/a character-set-server = utf8" ${CONF}

# To finalize installation

# Start the database service and configure it to start when the system boots:
echo
echo "** Starting mariadb service"
echo 

systemctl enable mariadb.service
systemctl start mariadb.service

# Secure the database service including choosing a suitable password for the root account:
echo
echo "** mysql_secure_installation. "
echo "**"
echo "** - Enter current password for root (enter for none): <enter> "
echo "** - Set root password: [Y/n] Y -> then set the password"
echo "** - Remove anonymous users? [Y/n] Y"
echo "** - Disallow root login remotely? [Y/n] Y"
echo "** - Remove test database and access to it? [Y/n] Y"
echo "** - Reload privilege tables now? [Y/n] Y"
echo
echo "*********************************************************************"
echo "**** Enter this password when you set the one : ${DATABASE_PASS} ****"
echo "*********************************************************************"

mysql_secure_installation

# To install the message queue service
echo
echo "** Installing rabbitmq service"
echo 

yum -y -q install rabbitmq-server

# To configure the message queue service
# Start the message queue service and configure it to start when the system boots:
echo
echo "** Starting rabbitmq service"
echo 

systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service

# Add the openstack user:
rabbitmqctl add_user openstack ${RABBIT_PASS}

# Permit configuration, write, and read access for the openstack user:
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

echo
echo "** Done."