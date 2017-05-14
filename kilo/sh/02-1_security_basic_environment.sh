#!/bin/sh -e

export LANG=en_US.utf8

PW_FILE=OPENSTACK_PASSWD.ini

cp -p ./${PW_FILE} ./${PW_FILE}.org

for i in `grep -v -e ^# -e ^$ ${PW_FILE} | awk '{print $1}'`
do
    pass=$(openssl rand -hex 10)
    sed -i "s/${i} =.*/${i} = ${pass}/" ./${PW_FILE}
done

echo
echo "** Created ${PW_FILE}. "
echo 