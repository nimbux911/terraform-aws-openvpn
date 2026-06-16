#!/bin/bash
set -euo pipefail

VOLUME_PATH="${volume_path}"
VPN_ENDPOINT="${vpn_endpoint}"
VPN_CLIENT_CIDR="${vpn_client_cidr}"
CONF_DIR="$VOLUME_PATH/conf"
CCD_DIR="$CONF_DIR/ccd"
STATE_DIR="$CONF_DIR/access-control"
DESIRED_USERS_FILE="$STATE_DIR/desired-users.txt"
ACTIVE_USERS_FILE="$STATE_DIR/active-users.txt"

cd "$VOLUME_PATH"

source "$CONF_DIR/ovpn_env.sh"

mkdir -p "$CCD_DIR" "$STATE_DIR"
if [ ! -f "$ACTIVE_USERS_FILE" ]; then
  find "$CONF_DIR/pki/issued" -maxdepth 1 -type f -name '*.crt' -exec basename {} .crt \; 2>/dev/null | grep -vxF "$OVPN_CN" | sort > "$ACTIVE_USERS_FILE" || true
fi

grep -q '^client-config-dir /etc/openvpn/ccd$' "$CONF_DIR/openvpn.conf" || echo 'client-config-dir /etc/openvpn/ccd' >> "$CONF_DIR/openvpn.conf"

cat > "$DESIRED_USERS_FILE" <<'EOF_USERS'
%{ for username, user in vpn_users ~}
${username}
%{ endfor ~}
EOF_USERS

while read -r username; do
  [ -z "$username" ] && continue
  [ "$username" = "$OVPN_CN" ] && continue
  if ! grep -qxF "$username" "$DESIRED_USERS_FILE"; then
    if [ -f "$CONF_DIR/pki/issued/$username.crt" ]; then
      docker compose run --rm openvpn ovpn_revokeclient "$username" remove || true
    fi
    rm -f "$CCD_DIR/$username"
  fi
done < "$ACTIVE_USERS_FILE"

%{ for username, user in vpn_users ~}
if [ ! -f "$CONF_DIR/pki/issued/${username}.crt" ]; then
  docker compose run --rm openvpn easyrsa build-client-full "${username}" nopass
fi
mkdir -p keys
docker compose run --rm openvpn ovpn_getclient "${username}" > "keys/${username}.ovpn"
sed -i -E "s#^remote .+ 1194 udp[[:space:]]*\$#remote $VPN_ENDPOINT 1194 udp#" "keys/${username}.ovpn"
printf 'ifconfig-push ${user.ip} 255.255.255.0\n' > "$CCD_DIR/${username}"
%{ endfor ~}

cp "$DESIRED_USERS_FILE" "$ACTIVE_USERS_FILE"

iptables -N OPENVPN_ACL 2>/dev/null || true
iptables -F OPENVPN_ACL
iptables -C FORWARD -j OPENVPN_ACL 2>/dev/null || iptables -I FORWARD 1 -j OPENVPN_ACL

docker exec openvpn iptables -N OPENVPN_ACL 2>/dev/null || true
docker exec openvpn iptables -F OPENVPN_ACL
docker exec openvpn iptables -C FORWARD -j OPENVPN_ACL 2>/dev/null || docker exec openvpn iptables -I FORWARD 1 -j OPENVPN_ACL

%{ for username, user in vpn_users ~}
%{ for cidr in vpn_access_groups[user.group].allowed_cidrs ~}
iptables -A OPENVPN_ACL -s ${user.ip}/32 -d ${cidr} -j ACCEPT
docker exec openvpn iptables -A OPENVPN_ACL -s ${user.ip}/32 -d ${cidr} -j ACCEPT
%{ endfor ~}
%{ endfor ~}

%{ for cidr in peered_networks ~}
iptables -A OPENVPN_ACL -s "$VPN_CLIENT_CIDR" -d ${cidr} -j DROP
docker exec openvpn iptables -A OPENVPN_ACL -s "$VPN_CLIENT_CIDR" -d ${cidr} -j DROP
%{ endfor ~}

iptables -A OPENVPN_ACL -j RETURN
docker exec openvpn iptables -A OPENVPN_ACL -j RETURN

chown -R ubuntu:ubuntu "$CCD_DIR" "$STATE_DIR"
