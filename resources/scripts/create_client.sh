
if [ $(whoami) == "root" ] && [ -n "$1" ] ; then
	sudo docker-compose run --rm openvpn easyrsa build-client-full $1 nopass
	sudo docker-compose run --rm openvpn ovpn_getclient $1 > ./keys/$1.ovpn
elif [ $(whoami) != "root" ]; then
	echo "It must be run as root."
	exit 1
elif [ -z "$1" ]; then
	echo "Please pass username as first parameter."
fi
