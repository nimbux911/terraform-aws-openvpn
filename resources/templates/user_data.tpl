#!/bin/bash
apt-get update
apt-get install docker.io docker-compose s3fs awscli -y
usermod -aG docker ubuntu

read -r -d '' DAEMON_JSON << EOM
{
  "bip": "${docker_cidr}"
}
EOM

sudo echo "$DAEMON_JSON" > /etc/docker/daemon.json

sudo service docker restart

aws ec2 disassociate-address --public-ip ${eip_address} --region ${aws_region}
aws ec2 associate-address --region ${aws_region} --instance-id "$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)" --allocation-id ${eip_allocation_id}

mkdir /openvpn

s3fs ${s3_bucket} /openvpn -o allow_other -o iam_role="auto" -o url="https://s3.${aws_region}.amazonaws.com"

chmod +x /openvpn/*.sh
chown -R ubuntu:ubuntu /openvpn

cd /openvpn

if [ ! -f /openvpn/conf/openvpn.conf ]; then
    docker-compose run --rm openvpn ovpn_genconfig -N -d \
                  %{ for route in routes  ~}
                    -p "route ${route}" \
                  %{ endfor ~}
                  -e 'topology subnet' -u udp://${eip_address}
    echo "openvpn" | docker-compose run --rm openvpn ovpn_initpki nopass
fi

docker-compose up -d openvpn