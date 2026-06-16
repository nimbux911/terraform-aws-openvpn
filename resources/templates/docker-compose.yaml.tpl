services:
  openvpn:
    cap_add:
     - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    image: ${openvpn_image}
    container_name: openvpn
    ports:
     - "1194:1194/udp"
    restart: always
    environment:
     - EASYRSA_BATCH=1
    volumes:
     - ./conf:/etc/openvpn

networks:
  default:
    ipam:
      driver: default
      config:
        - subnet: ${compose_cidr}
