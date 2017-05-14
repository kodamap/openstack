#!/bin/sh -e

# this scripts is origined from 
# https://github.com/josug-book1-materials/chapter05-10

LANG=en_US.utf8

if [[ -z $1 ]]; then
    echo "** Usage: $0 <Controller IP>"
    exit 0
fi

controller=$1

    cat << EOF > ./userdata_step-server.txt
#!/bin/bash
cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
yum install -q -y git
cd /root
git clone https://github.com/josug-book1-materials/install_cli.git
cd install_cli && sh install.sh

echo "export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=SNSApp
export OS_TENANT_NAME=SNSApp
export OS_USERNAME=snsapp-infra-user
export OS_PASSWORD=password" >> ~/openrc
export OS_AUTH_URL=http://${controller}:5000/v3
export PS1='[\u@\h \W(snsapp-infra-user)]\$ '" >> ~/openrc

EOF


source ~/openrc

function get_uuid () { cat - | grep " id " | awk '{print $4}'; }
export MY_WORK_NET=`neutron net-show work-net | get_uuid`

nova boot --flavor standard.xsmall --image "centos6-base" \
  --key-name key-for-step-server \
  --security-groups sg-for-step-server \
  --user-data userdata_step-server.txt \
  --nic net-id=${MY_WORK_NET} step-server

