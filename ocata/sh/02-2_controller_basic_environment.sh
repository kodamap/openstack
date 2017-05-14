#!/bin/sh -e

export LANG=en_US.utf8
timedatectl set-timezone Asia/Tokyo

export LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <controller node IP>"
    exit 1
fi

controller=$1

function get_passwd () { grep ^$1 ${PW_FILE} | awk -F= '{print $2}' | sed 's/ //g'; }

# Get the Password from OPENSTACK_PASSWD.ini
PW_FILE=OPENSTACK_PASSWD.ini

# To Fix the password , Edit these paramters manually.
DATABASE_PASS=`grep ^DATABASE_PASS OPENSTACK_PASSWD.ini | awk -F= '{print $2}' | sed 's/ //g'`
RABBIT_PASS=`grep ^RABBIT_PASS OPENSTACK_PASSWD.ini | awk -F= '{print $2}' | sed 's/ //g'`

disable_firewalld () {

  # Disable firewall
  echo
  echo "** Disabling firewalld..."
  echo

  yum -y install firewalld
  systemctl stop firewalld
  systemctl disable firewalld
}

generate_sshkey () {

  # To generate ssh-key

  echo
  echo "** Generating ssh key-pair..."
  echo

  ssh-keygen -t rsa -N ""
}

install_ntp () {

  # To install the NTP service
  echo
  echo "** Installing chrony packages."
  echo

  yum -y install chrony

  # To configure the NTP service
  CONF=/etc/chrony.conf
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  if grep "^allow " ${CONF} > /dev/null ; then
     cp -pf ${CONF}.org ${CONF}
  fi

  echo "allow 192.168.0.0/16" >> ${CONF}
  echo "allow 172.31.0.0/16" >> ${CONF}
  echo "allow 10.0.0.0/8" >> ${CONF}

  systemctl enable chronyd.service
  systemctl start chronyd.service

  echo
  echo "** Configured and Started the NTP service."
  echo

  echo
  echo "** chronyc sources"
  echo
  chronyc sources

}

install_openstack_package () {
  echo
  echo "** Enable OpenStack Repository..."
  echo

  # To configure prerequisites
  # Install the rdo-release-ocata package to enable the RDO repository:
  # On CentOS, the extras repository provides the RPM that enables the OpenStack repository.
  # CentOS includes the extras repository by default, so you can simply install the package to enable the OpenStack repository.

  if [ ! -f /etc/yum.repos.d/CentOS-OpenStack-ocata.repo ] ; then
      yum install centos-release-openstack-ocata -y
  fi

  # To finalize installation
  # Upgrade the packages on your system:
  echo
  echo "** upgrading your system....this will take a few more minutes"
  echo

  yum -y upgrade

  echo
  echo "** upgrading done."
  echo

  echo
  echo "** Installing packages..."
  echo

  # Install the OpenStack client:
  yum install python-openstackclient -y

  # RHEL and CentOS enable SELinux by default. Install the openstack-selinux package to
  # automatically manage security policies for OpenStack services:
  yum -y install openstack-selinux

  # To install openstack-config
  yum -y install openstack-utils

}

install_database () {
  # To install and configure the database server
  yum install mariadb mariadb-server python2-PyMySQL -y

  # Create and edit the /etc/my.cnf.d/openstack.cnf file from /etc/my.cnf.d/mariadb-server.cnf
  CONF=/etc/my.cnf.d/openstack.cnf
  cp -p /etc/my.cnf.d/mariadb-server.cnf ${CONF}

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
  sed -i "/^\[mysqld\]$/a character-set-server = utf8" ${CONF}

  # To finalize installation

  # Start the database service and configure it to start when the system boots:
  echo
  echo "** Starting mariadb service"
  echo

  systemctl enable mariadb.service
  systemctl start mariadb.service

  # Secure the database service including choosing a suitable password for the root account:
  echo "Changing root password"; sleep 1
  mysql -uroot -e "UPDATE mysql.user SET Password=PASSWORD('${DATABASE_PASS}') WHERE User='root';"
  echo "Removing anonymous users"; sleep 1
  mysql -uroot -e "DELETE FROM mysql.user WHERE User='';"
  echo "Disallowing root login remotely"; sleep 1
  mysql -uroot -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  echo "Removing test database and access to it"; sleep 1
  mysql -uroot -e "DROP DATABASE IF EXISTS test;"
  mysql -uroot -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  echo "flash privileges"; sleep 1
  mysql -uroot -e "FLUSH PRIVILEGES;"

  #echo
  #echo "** mysql_secure_installation. "
  #echo "**"
  #echo "** - Enter current password for root (enter for none): <enter> "
  #echo "** - Set root password: [Y/n] Y -> then set the password"
  #echo "** - Remove anonymous users? [Y/n] Y"
  #echo "** - Disallow root login remotely? [Y/n] Y"
  #echo "** - Remove test database and access to it? [Y/n] Y"
  #echo "** - Reload privilege tables now? [Y/n] Y"
  #echo
  # echo "*********************************************************************"
  # echo "**** Enter this password when you set the one : ${DATABASE_PASS} ****"
  # echo "*********************************************************************"

  # mysql_secure_installation
  
}

install_message_queue () {
  # To install the message queue service
  echo
  echo "** Installing rabbitmq service"
  echo

  yum -y install rabbitmq-server

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

}

install_memcached () {
  # Install the packages:

  echo
  echo "** Installing the memcached packages..."
  echo

  yum -y install memcached python-memcached

  CONF=/etc/sysconfig/memcached
  echo
  echo "** Editing the ${CONF}..."
  echo

  test ! -f ${CONF}.org && cp -p ${CONF} ${CONF}.org

  sed -i 's/OPTIONS=.*/OPTIONS="-l 0.0.0.0 -U 11211 -t 4"/' ${CONF}
  
  systemctl enable memcached.service
  systemctl start memcached.service
  systemctl status memcached.service

}

# main

disable_firewalld
generate_sshkey
install_ntp
install_openstack_package
install_database
install_message_queue
install_memcached

echo
echo "** Done."
