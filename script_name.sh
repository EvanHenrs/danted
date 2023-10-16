#!/bin/bash
# Check if user provided two IP addresses, a gateway, and a port
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <IP1> <IP2> <GATEWAY> <PORT>"
    exit 1
fi
# Assign IP addresses, gateway, and port to variables
IP1=$1
IP2=$2
GATEWAY=$3
PORT=$4
# Check if dos2unix is installed
if ! command -v dos2unix &> /dev/null; then
    echo "dos2unix could not be found, installing..."
    sudo apt-get update
    sudo apt-get install -y dos2unix
fi

# Backup original interfaces file
sudo cp /etc/network/interfaces /etc/network/interfaces.backup

# Create new interfaces file
echo "# The loopback network interface
auto lo
iface lo inet loopback

# Primary network interface
auto eth0
iface eth0 inet static
    address $IP1
    netmask 255.255.255.0
    gateway $GATEWAY

# Alias for eth0 to add second IP
auto eth0:1
iface eth0:1 inet static
    address $IP2
    netmask 255.255.255.0" | sudo tee /etc/network/interfaces > /dev/null

# Restart networking to apply changes
sudo /etc/init.d/networking restart
sudo /etc/init.d/sockd stop

# Dante Socks5 Proxy common configuration
DANTE_COMMON="
clientmethod: none
socksmethod: pam.username none
user.privileged: root
user.notprivileged: sockd

client pass {
    from: 0/0  to: 0/0
    log: connect disconnect
}
client block {
    from: 0/0 to: 0/0
    log: connect error
}
socks pass {
    from: 0/0 to: 0/0
    socksmethod: pam.username
    log: connect disconnect
}
socks block {
    from: 0/0 to: 0/0
    log: connect error
}
"

# Configure Dante Socks5 Proxy for IP1
DANTE_CONFIG_1="/etc/danted/danted_${IP1}.conf"
echo "internal: $IP1  port = $PORT
external: $IP1
logoutput: /var/log/sockd_${IP1}.log
$DANTE_COMMON" | sudo tee $DANTE_CONFIG_1 > /dev/null

# Configure Dante Socks5 Proxy for IP2
DANTE_CONFIG_2="/etc/danted/danted_${IP2}.conf"
echo "internal: $IP2  port = $PORT
external: $IP2
logoutput: /var/log/sockd_${IP2}.log
$DANTE_COMMON" | sudo tee $DANTE_CONFIG_2 > /dev/null

# Convert Dante configuration files to Unix format using dos2unix
sudo dos2unix $DANTE_CONFIG_1
sudo dos2unix $DANTE_CONFIG_2

# Start Dante Socks5 Proxy instances
sudo nohup sockd -f $DANTE_CONFIG_1 -p /var/run/danted_${IP1}.pid &
sudo nohup sockd -f $DANTE_CONFIG_2 -p /var/run/danted_${IP2}.pid &

echo "Network and Dante Socks5 proxy configuration applied successfully!"
