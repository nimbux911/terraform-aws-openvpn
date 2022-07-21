if [ $(whoami) == "ubuntu" ] && [ -n "$1" ] ; then
	sudo docker-compose run --rm openvpn ovpn_revokeclient $1 remove
	echo "Client $1 has been removed."
	rm ./keys/$1.ovpn
elif [ $(whoami) != "ubuntu" ]; then
	echo "It must be run as ubuntu."
	exit 1
elif [ -z "$1" ]; then
	echo "Please pass username as first parameter."
fi