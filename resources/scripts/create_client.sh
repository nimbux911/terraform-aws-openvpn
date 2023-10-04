
if [ $(whoami) == "ubuntu" ] && [ -n "$1" ] ; then
    mkdir -p ./keys
	docker compose run --rm openvpn easyrsa build-client-full $1 nopass
	docker compose run --rm openvpn ovpn_getclient $1 > ./keys/$1.ovpn
elif [ $(whoami) != "ubuntu" ]; then
	echo "This script must be ran as ubuntu."
	exit 1
elif [ -z "$1" ]; then
	echo "Please give a username as first parameter."
fi
