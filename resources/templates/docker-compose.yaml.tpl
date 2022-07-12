version: '2'
services:
  openvpn:
    cap_add:
     - NET_ADMIN
    image: kylemanna/openvpn
    container_name: openvpn
    ports:
     - "1194:1194/udp"
    restart: always
    volumes:
     - ./conf:/etc/openvpn

networks:
  default:
    ipam:
      driver: default
      config:
        - subnet: ${compose_cidr}
