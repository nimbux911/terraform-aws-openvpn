#!/bin/bash

set -euo pipefail

main(){
  install_dependencies
  mount_volume
  create_files
  config_openvpn
}

get_instance_id(){
  local token
  token=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  curl -fsS -H "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/instance-id"
}

get_volume_device(){
  local volume_serial
  local device

  volume_serial=$(echo "${volume_id}" | tr -d '-')
  for _ in $(seq 1 30); do
    device=$(lsblk -ndo NAME,SERIAL | awk -v serial="$volume_serial" '$2 == serial { print $1; exit }')
    if [ -n "$device" ]; then
      echo "/dev/$device"
      return 0
    fi
    sleep 2
  done

  echo "Unable to find attached EBS volume ${volume_id} by serial $volume_serial" >&2
  lsblk -o NAME,TYPE,MOUNTPOINTS,FSTYPE,SIZE,SERIAL >&2
  return 1
}

mount_volume(){
  local instance_id
  local device
  instance_id=$(get_instance_id)

  aws ec2 attach-volume --region ${aws_region} \
  --instance-id "$instance_id" \
  --device ${volume_device_name} \
  --volume-id ${volume_id}
  device=$(get_volume_device)
  mkdir -p ${volume_path}
  mount "$device" ${volume_path} || echo "Creating $device fs..." > init.log 
  if [ -f init.log ]; then
    mkfs -t xfs "$device"
    mount "$device" ${volume_path}
    rm init.log
  fi
  cd ${volume_path}
}

install_dependencies(){
  apt-get update
  apt-get install -y awscli jq curl ca-certificates gnupg
  if apt-cache show amazon-ssm-agent >/dev/null 2>&1; then
    apt-get install -y amazon-ssm-agent
    systemctl enable --now amazon-ssm-agent
  elif command -v snap >/dev/null 2>&1; then
    snap install amazon-ssm-agent --classic || true
    systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true
  fi
  # docker
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  usermod -aG docker ubuntu
}

retry_command(){
  local timeout_seconds="$1"
  local attempts="$2"
  shift 2

  for attempt in $(seq 1 "$attempts"); do
    if timeout "$timeout_seconds" "$@"; then
      return 0
    fi

    echo "Command failed or timed out on attempt $attempt/$attempts: $*"
    systemctl restart docker || true
    sleep $((attempt * 10))
  done

  return 1
}

prepare_openvpn_image(){
  systemctl enable --now docker
  retry_command 180 5 docker pull ${openvpn_image}
}

docker_compose_run(){
  retry_command 120 3 docker compose run --rm --pull never openvpn "$@"
}

start_openvpn(){
  retry_command 120 3 docker compose up -d --no-build --pull never openvpn
}

create_files(){
  cat > /etc/docker/daemon.json <<'EOF'
{
  "bip": "${docker_cidr}"
}
EOF

  cat > docker-compose.yml <<'EOF'
${docker_compose}
EOF

  cat > create_client.sh <<'EOF'
${create_client}
EOF

  cat > revoke_client.sh <<'EOF'
${revoke_client}
EOF

  chmod +x create_client.sh revoke_client.sh

}

config_openvpn(){

  aws ec2 associate-address --region ${aws_region} --instance-id "$(get_instance_id)" --allocation-id ${eip_allocation_id} --allow-reassociation
  prepare_openvpn_image

  if [ ! -f ${volume_path}/conf/openvpn.conf ]; then
      docker_compose_run ovpn_genconfig -N -d \
                    %{ for route in routes  ~}
                    -p "route ${route}" \
                    %{ endfor ~}
                    -e 'topology subnet' -u udp://${vpn_endpoint}
      timeout 1200 sh -c 'printf "openvpn\n" | docker compose run -T --rm --pull never openvpn ovpn_initpki nopass'
  fi

  sed -i -E 's#^remote .+ 1194 udp$#remote ${vpn_endpoint} 1194 udp#' ${volume_path}/conf/openvpn.conf
  if [ -f ${volume_path}/conf/ovpn_env.sh ]; then
    sed -i -E 's#^declare -x OVPN_SERVER_URL=.*#declare -x OVPN_SERVER_URL=udp://${vpn_endpoint}#' ${volume_path}/conf/ovpn_env.sh
  fi

  SERVER_CERT=$(sed -n -E 's#^cert /etc/openvpn/(.+)$#${volume_path}/conf/\1#p' ${volume_path}/conf/openvpn.conf)
  SERVER_KEY=$(sed -n -E 's#^key /etc/openvpn/(.+)$#${volume_path}/conf/\1#p' ${volume_path}/conf/openvpn.conf)
  if [ ! -f "$SERVER_CERT" ] || [ ! -f "$SERVER_KEY" ]; then
    docker_compose_run easyrsa build-server-full ${vpn_endpoint} nopass
    sed -i -E 's#^key /etc/openvpn/pki/private/.+#key /etc/openvpn/pki/private/${vpn_endpoint}.key#' ${volume_path}/conf/openvpn.conf
    sed -i -E 's#^cert /etc/openvpn/pki/issued/.+#cert /etc/openvpn/pki/issued/${vpn_endpoint}.crt#' ${volume_path}/conf/openvpn.conf
    sed -i -E 's#^declare -x OVPN_CN=.*#declare -x OVPN_CN=${vpn_endpoint}#' ${volume_path}/conf/ovpn_env.sh
  fi

  mkdir -p ${volume_path}/conf/ccd
  grep -q '^client-config-dir /etc/openvpn/ccd$' ${volume_path}/conf/openvpn.conf || echo 'client-config-dir /etc/openvpn/ccd' >> ${volume_path}/conf/openvpn.conf

  chown -R ubuntu:ubuntu .

  start_openvpn

}

main "$@"
