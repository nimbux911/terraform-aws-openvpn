
if [ $(whoami) == "ubuntu" ] && [ -n "$1" ] ; then
    mkdir -p ./keys
	sudo docker-compose run --rm openvpn easyrsa build-client-full $1 nopass
	sudo docker-compose run --rm openvpn ovpn_getclient $1 > ./keys/$1.ovpn
elif [ $(whoami) != "ubuntu" ]; then
	echo "It must be run as ubuntu."
	exit 1
elif [ -z "$1" ]; then
	echo "Please pass username as first parameter."
fi
