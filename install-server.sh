#!/bin/bash

#OpenVPN Server configuration script for Mikrotik RouterOS OVPN Client
#Supported Linux distributives (x86_64/amd64 only):
#CentOS 7, 8
#Debian 9, 10
#Ubuntu 18.04, 20.04

OPENVPN_USER="nobody"
OPENVPN_GROUP="nogroup"
OPENVPN_CONFIG_DIR="/etc/openvpn"
OPENVPN_SERVICE_NAME="openvpn"

if [ -f "/etc/debian_version" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get -y install openvpn openssl
elif [ -f "/etc/centos-release" ]; then
        OPENVPN_USER="openvpn"
        OPENVPN_GROUP="openvpn"
        if [ -f "/etc/os-release" ]; then
                source /etc/os-release;
                yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-${VERSION_ID}.noarch.rpm
                if [ "$VERSION_ID" == "8" ]; then
                        OPENVPN_CONFIG_DIR="/etc/openvpn/server"
                        OPENVPN_SERVICE_NAME="openvpn-server"
                        if [ ! -d "$OPENVPN_CONFIG_DIR" ]; then
                                mkdir $OPENVPN_CONFIG_DIR;
                        fi
                fi
        fi
        yum -y install openvpn openssl
else
        echo "Distributive not supported";
        exit
fi

if [ -f "/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so" ]; then
        AUTH_PLUGIN="plugin /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so login"
elif [ -f "/usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so" ]; then
        AUTH_PLUGIN="plugin /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so login"
elif [ -f "/usr/lib/openvpn/openvpn-plugin-auth-pam.so" ]; then
        AUTH_PLUGIN="plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so login"
else
        echo "openvpn-plugin-auth-pam.so not found";
        exit;
fi

        PORT=1190

if [ ! -d "/etc/openvpn/mikrotik-ssl" ]; then
        mkdir /etc/openvpn/mikrotik-ssl
fi

#Server certificate
openssl genrsa -out /etc/openvpn/mikrotik-ssl/ca-${PORT}.key 4096 > /dev/null

openssl req -x509 -days 3650 -new -key /etc/openvpn/mikrotik-ssl/ca-${PORT}.key \
    -out /etc/openvpn/mikrotik-ssl/ca-${PORT}.crt \
    -subj '/C=SK/ST=Bratislava/L=Bratislava/CN=root'

openssl genrsa -out /etc/openvpn/mikrotik-ssl/server-${PORT}.key 4096

openssl req -new -key /etc/openvpn/mikrotik-ssl/server-${PORT}.key \
    -out /etc/openvpn/mikrotik-ssl/server-${PORT}.crt \
    -subj '/C=SK/ST=Bratislava/L=Bratislava/CN=server'

openssl x509 -req -days 3650 -in /etc/openvpn/mikrotik-ssl/server-${PORT}.crt \
    -CA /etc/openvpn/mikrotik-ssl/ca-${PORT}.crt -CAkey /etc/openvpn/mikrotik-ssl/ca-${PORT}.key \
    -set_serial 01 -out /etc/openvpn/mikrotik-ssl/server-${PORT}.crt

openssl dhparam -out /etc/openvpn/mikrotik-ssl/dh2048-${PORT}.pem 2048

#Client certificate
openssl genrsa -out /etc/openvpn/mikrotik-ssl/client-${PORT}.key 4096

openssl req -new -key /etc/openvpn/mikrotik-ssl/client-${PORT}.key \
    -out /etc/openvpn/mikrotik-ssl/client-${PORT}.crt \
    -subj '/C=SK/ST=Bratislava/L=Bratislava/CN=client'

openssl x509 -req -days 3650 -in /etc/openvpn/mikrotik-ssl/client-${PORT}.crt \
    -CA /etc/openvpn/mikrotik-ssl/ca-${PORT}.crt -CAkey /etc/openvpn/mikrotik-ssl/ca-${PORT}.key \
    -set_serial 01 -out /etc/openvpn/mikrotik-ssl/client-${PORT}.crt


while true;
do
        SUB1=2
        SUB2=2
        if [[ $(ip route | grep "10.${SUB1}.${SUB2}.0/24" | wc -l) == "0 ]]; then
                break;
        fi
done

cat <<EOF > ${OPENVPN_CONFIG_DIR}/server${PORT}.conf
daemon
mode server
tls-server
port $PORT
proto tcp
dev tun${PORT}
log /var/log/openvpn-$PORT.log
status /var/log/openvpn-status-$PORT.log
ca /etc/openvpn/mikrotik-ssl/ca-${PORT}.crt
cert /etc/openvpn/mikrotik-ssl/server-${PORT}.crt
key /etc/openvpn/mikrotik-ssl/server-${PORT}.key
dh /etc/openvpn/mikrotik-ssl/dh2048-${PORT}.pem
topology subnet
server 10.${SUB1}.${SUB2}.0 255.255.255.0
client-to-client
ifconfig-pool-persist ipp.txt
username-as-common-name
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
user $OPENVPN_USER
group $OPENVPN_GROUP
keepalive 10 120
persist-key
persist-tun
auth sha1
cipher AES-256-CBC
verb 5
script-security 2
up /etc/openvpn/server-up.sh
down /etc/openvpn/server-down.sh
EOF

echo $AUTH_PLUGIN >> ${OPENVPN_CONFIG_DIR}/server${PORT}.conf;

NETWORK_DEVICE=$(ip route | grep default | awk '{print $5}' | head -n1);
IPTABLES=$(/bin/which iptables);

echo '#!/bin/bash' > /etc/openvpn/server-up.sh;
echo "echo 1 > /proc/sys/net/ipv4/ip_forward" >> /etc/openvpn/server-up.sh;
echo "${IPTABLES} -t nat -A POSTROUTING -o ${NETWORK_DEVICE} -j MASQUERADE" >> /etc/openvpn/server-up.sh;

echo '#!/bin/bash' > /etc/openvpn/server-down.sh;
echo "${IPTABLES} -t nat -D POSTROUTING -o ${NETWORK_DEVICE} -j MASQUERADE" >> /etc/openvpn/server-down.sh;

chmod +x /etc/openvpn/server-up.sh;
chmod +x /etc/openvpn/server-down.sh;

VPN_USER=mikrotik${PORT}
VPN_PASSWORD=$(openssl rand -base64 32)

useradd -M -s /bin/false $VPN_USER
echo "${VPN_USER}:${VPN_PASSWORD}" | chpasswd

systemctl enable ${OPENVPN_SERVICE_NAME}@server${PORT}.service > /dev/null
systemctl start ${OPENVPN_SERVICE_NAME}@server${PORT}.service > /dev/null

echo "=================================="
echo "=======-Client Certificate-======="
echo "=================================="
cat /etc/openvpn/mikrotik-ssl/client-${PORT}.crt;
echo "=================================="
echo "=======-Client Private Key-======="
echo "=================================="
cat /etc/openvpn/mikrotik-ssl/client-${PORT}.key;
echo "=================================="
echo "========-Login Credentials-======="
echo "=================================="
echo "OpenVPN Port: $PORT"
echo "OpenVPN USERNAME: ${VPN_USER}"
echo "OpenVPN PASSWORD: ${VPN_PASSWORD}"
echo "=================================="
echo "Stop OpenVPN Server: systemctl stop ${OPENVPN_SERVICE_NAME}@server${PORT}.service"
echo "Start OpenVPN Server: systemctl start ${OPENVPN_SERVICE_NAME}@server${PORT}.service"
echo "Disable OpenVPN Server: systemctl disable ${OPENVPN_SERVICE_NAME}@server${PORT}.service"
echo "Enable OpenVPN Server: systemctl enable ${OPENVPN_SERVICE_NAME}@server${PORT}.service"
