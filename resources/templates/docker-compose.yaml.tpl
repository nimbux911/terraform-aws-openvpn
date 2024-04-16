version: '2'
services:
  openvpn:
    cap_add:
     - NET_ADMIN
    image: public.ecr.aws/n5x5g3h7/nimbux911/dockovpn:2.6.8-config.0.1.0
    container_name: openvpn
    ports:
     - "1194:1194/udp"
    restart: always
    environment:
     - DEBUG=1
     - EASYRSA_BATCH=1
    volumes:
     - ./conf:/etc/openvpn

networks:
  default:
    ipam:
      driver: default
      config:
        - subnet: ${compose_cidr}
