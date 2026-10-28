#!/bin/bash
set -euo pipefail
umask 077

VOLUME_PATH="${volume_path}"
VPN_ENDPOINT="${vpn_endpoint}"
VPN_CLIENT_CIDR="${vpn_client_cidr}"
VPN_NETMASK="${cidrnetmask(vpn_client_cidr)}"
CONF_DIR="$VOLUME_PATH/conf"
CCD_DIR="$CONF_DIR/ccd"
KEYS_DIR="$VOLUME_PATH/keys"

fail() { echo "Profile sync aborted: $*" >&2; exit 1; }

ipv4_number() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  echo "$(( (10#$a << 24) + (10#$b << 16) + (10#$c << 8) + 10#$d ))"
}

DESIRED_USERS=$(cat <<'EOF_USERS'
%{ for username, user in vpn_users ~}
${username}	${user.ip == null ? "-" : user.ip}
%{ endfor ~}
EOF_USERS
)

# This path deliberately never invokes the authoritative ACL/revocation script.
# Lock concurrent additive SSM runs; no compose up/run/restart is needed.
test -d "$CCD_DIR" || fail "CCD directory is missing; refusing to alter server configuration."
exec 9>"$CONF_DIR/.profile-sync.lock"
flock -n 9 || fail "Another profile sync is running."
test "$(docker inspect -f '{{.State.Running}}' openvpn)" = true || fail "OpenVPN is not running."
grep -qxF 'client-config-dir /etc/openvpn/ccd' "$CONF_DIR/openvpn.conf" || fail "CCD is not enabled."
grep -qxF 'topology subnet' "$CONF_DIR/openvpn.conf" || fail "Only topology subnet is supported."

read -r SERVER_NETWORK SERVER_NETMASK SERVER_OPTION < <(awk '$1 == "server" {print $2, $3, $4}' "$CONF_DIR/openvpn.conf")
test "$SERVER_NETWORK/$SERVER_NETMASK" = "$${VPN_CLIENT_CIDR%/*}/$VPN_NETMASK" || fail "vpn_client_cidr does not match the running server."
NETWORK=$(ipv4_number "$SERVER_NETWORK")
MASK=$(ipv4_number "$SERVER_NETMASK")
BROADCAST=$(( NETWORK | (4294967295 ^ MASK) ))
POOL_START=$(( NETWORK + 2 ))
POOL_END=$(( BROADCAST - 2 ))
read -r EXPLICIT_POOL_START EXPLICIT_POOL_END <<< "$(awk '$1 == "ifconfig-pool" {print $2, $3}' "$CONF_DIR/openvpn.conf")"
if [ -n "$EXPLICIT_POOL_START" ]; then
  POOL_START=$(ipv4_number "$EXPLICIT_POOL_START")
  POOL_END=$(ipv4_number "$EXPLICIT_POOL_END")
fi
# nopool disables only the implicit pool; an explicit ifconfig-pool is still active.
POOL_ENABLED=1
if [ "$SERVER_OPTION" = nopool ] && [ -z "$EXPLICIT_POOL_START" ]; then
  POOL_ENABLED=0
fi
STATUS_PATH=$(awk '$1 == "status" {print $2}' "$CONF_DIR/openvpn.conf")
test -n "$STATUS_PATH" || fail "A client status file is required for collision checks."
CLIENT_STATUS=$(docker exec openvpn cat "$STATUS_PATH")

# Validate the entire inventory before creating any certificate, CCD or profile.
while IFS=$'\t' read -r username ip; do
  [ -n "$username" ] || continue
  CERT="$CONF_DIR/pki/issued/$username.crt"
  CCD="$CCD_DIR/$username"
  CERT_STATUS=$(awk -F '\t' -v cn="/CN=$username" '$NF == cn {status=$1} END {print status}' "$CONF_DIR/pki/index.txt")
  if [ -f "$CERT" ]; then
    test "$CERT_STATUS" = V || fail "$username is not a valid registered client; refusing to reissue it."
    docker exec openvpn openssl x509 -checkend 0 -noout -in "/etc/openvpn/pki/issued/$username.crt" >/dev/null || fail "$username has an expired certificate."
    test -f "$CONF_DIR/pki/private/$username.key" || fail "$username has no private key; refusing to replace it."
  else
    test -z "$CERT_STATUS" || fail "$username already exists in the PKI registry; refusing to recreate it."
  fi
  [ "$ip" != - ] || continue
  IP_NUMBER=$(ipv4_number "$ip")
  (( IP_NUMBER > NETWORK + 1 && IP_NUMBER < BROADCAST && (IP_NUMBER & MASK) == NETWORK )) || fail "$ip is not an available client address in $VPN_CLIENT_CIDR."
  if [ -f "$CCD" ]; then
    test "$(awk '$1 == "ifconfig-push" {print $2, $3}' "$CCD")" = "$ip $VPN_NETMASK" || fail "$username has a different CCD; refusing to change its address."
  else
    test ! -f "$CERT" || fail "$username already uses dynamic addressing; omit ip to adopt it without changes."
  fi
  for other_ccd in "$CCD_DIR"/*; do
    [ -f "$other_ccd" ] || continue
    [ "$other_ccd" != "$CCD" ] || continue
    if awk -v ip="$ip" '$1 == "ifconfig-push" && $2 == ip {found=1} END {exit !found}' "$other_ccd"; then
      fail "$ip is already reserved in $other_ccd."
    fi
  done
  if [ ! -f "$CERT" ]; then
    if [ "$POOL_ENABLED" = 1 ] && (( IP_NUMBER >= POOL_START && IP_NUMBER <= POOL_END )); then
      fail "$ip overlaps the dynamic pool; choose an address outside it without changing the running server."
    fi
    if awk -F, -v ip="$ip" '$1 == ip || ($1 == "CLIENT_LIST" && $4 == ip) || ($1 == "ROUTING_TABLE" && $2 == ip) {found=1} END {exit !found}' <<< "$CLIENT_STATUS"; then
      fail "$ip is currently assigned to a connected client."
    fi
  fi
done <<< "$DESIRED_USERS"

mkdir -p "$KEYS_DIR"
TEMP_FILE=""
trap 'if [ -n "$TEMP_FILE" ]; then rm -f "$TEMP_FILE"; fi' EXIT
while IFS=$'\t' read -r username ip; do
  [ -n "$username" ] || continue
  CERT="$CONF_DIR/pki/issued/$username.crt"
  CCD="$CCD_DIR/$username"
  if [ "$ip" != - ] && [ ! -f "$CCD" ]; then
    TEMP_FILE=$(mktemp "$CCD_DIR/.profile-sync.XXXXXX")
    printf 'ifconfig-push %s %s\n' "$ip" "$VPN_NETMASK" > "$TEMP_FILE"
    # OpenVPN reads CCDs after dropping privileges to its unprivileged user.
    chmod 644 "$TEMP_FILE"
    mv "$TEMP_FILE" "$CCD"
    TEMP_FILE=""
  fi
  if [ ! -f "$CERT" ]; then
    docker exec -e EASYRSA_BATCH=1 openvpn easyrsa build-client-full "$username" nopass
  fi
  if [ ! -f "$KEYS_DIR/$username.ovpn" ]; then
    TEMP_FILE=$(mktemp "$KEYS_DIR/.profile-sync.XXXXXX")
    docker exec openvpn ovpn_getclient "$username" > "$TEMP_FILE"
    sed -i -E "s#^remote .+ 1194 udp[[:space:]]*\$#remote $VPN_ENDPOINT 1194 udp#" "$TEMP_FILE"
    chmod 600 "$TEMP_FILE"
    chown ubuntu:ubuntu "$TEMP_FILE"
    mv "$TEMP_FILE" "$KEYS_DIR/$username.ovpn"
    TEMP_FILE=""
    echo "Created profile: $username"
  else
    echo "Preserved profile: $username"
  fi
done <<< "$DESIRED_USERS"

echo "Additive profile sync complete. No revocations, firewall changes, server configuration changes or restarts."
