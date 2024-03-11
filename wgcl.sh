#!/bin/bash
# author: rxfatalslash

CRE=$(tput setaf 1)
CGR=$(tput setaf 2)
BLD=$(tput bold)
CNC=$(tput sgr0)

declare -g ip=""
declare -g dns=""

full_install() {
    distro="$(cat /etc/os-release | cut -d '=' -f2 | sed -e 's/"//g' | awk 'NR==1 {print $1}')"
    case $distro in
        ["Ubuntu""Debian"]*)
            printf "%s%sDebian based system detected%s" "$CBL" "$CGR" "$CNC"
            if ! dpkg -l | grep -iq "wireguard"; then
                apt-get install -y wireguard
            fi

            if ! dpkg -l | grep -iq "qrencode"; then
                apt-get install -y qrencode
            fi
        ;;
        ["Arch Linux""Arch"]*)
            printf "%s%sArch based system detected%s" "$CBL" "$CGR" "$CNC"
            if ! pacman -Qs wireguard-tools; then
                pacman -Sy wireguard-tools --noconfirm
            fi

            if ! pacman -Qs qrencode; then
                pacman -Sy qrencode --noconfirm
            fi
        ;;
    esac
    install_wireguard
}

install_wireguard() {
    if [ ! -d /etc/wireguard/keys ]; then
        mkdir -p /etc/wireguard/keys
    fi

    wg genkey > /etc/wireguard/keys/server.key
    cat /etc/wireguard/keys/server.key | wg pubkey > /etc/wireguard/keys/server.key.pub

    int=$(ip -o -4 route show to default | awk '{print $5}')
    pkey=$(cat /etc/wireguard/keys/server.key)
    read -rp "What IP do you want for the Wireguard server?: [10.0.0.1] " ip

    if -z $ip; then
        ip="10.0.0.1"
    fi

    echo -e "[Interface]
Address = $ip/24
ListenPort = 51820
PrivateKey = $pkey
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $int -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $int -j MASQUERADE
SaveConfig = true" > /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf /etc/wireguard/keys/server.key

    wg-quick up wg0
    systemctl enable wg-quick@wg0.service
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
    sysctl -p
}

new_client() {
    if [ ! -d /etc/wireguard/clients ]; then
        mkdir -p /etc/wireguard/clients
    fi

    while true; do
        read -rp "What's the device's name?: " client
        if [ ! -z $client ]; then
            break
        else
            clear
            printf "[ %s%sERROR%s ] Introduce a device name"
        fi
    done

    wg genkey > /etc/wireguard/clients/"$client".key
    cat /etc/wireguard/clients/"$client".key | wg pubkey > /etc/wireguard/clients/"$client".key.pub

    priv_key=$(cat /etc/wireguard/clients/"$client".key)
    pub_server_key=$(cat /etc/wireguard/keys/server.key.pub)
    pub_key=$(cat /etc/wireguard/clients/"$client".key.pub)
    pub_ip=$(curl ipinfo.io/ip)

    clear
    read -rp "What is the client's IP: " client_ip
    while true; do
        clear
        printf "%s%s1.%s Cloudflare\n
%s%s2.%s Google\n
%s%s3.%s Custom\n\n" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC"
        read -rp "Choose a DNS option: [1-3] " opt
        case $opt in
            1)
		dns="1.1.1.1, 1.0.0.1"
		break
	    ;;
            2)
		dns="8.8.8.8, 8.8.4.4"
		break
	    ;;
            3)
		read -rp "Enter a custom DNS: " dns
		break
	    ;;
        esac
    done

    echo -e "[Interface]
PrivateKey = $priv_key
Address = $client_ip
DNS = $dns

[Peer]
PublicKey = $pub_server_key
AllowedIPs = 0.0.0.0/24
Endpoint = $pub_ip:51820" > /etc/wireguard/clients/"$client".conf

    wg set wg0 peer $pub_key allowed-ips $client_ip
}

generate_qr() {
    clear
    dir="/etc/wireguard/clients"
    files=($(ls $dir | grep ".conf"))

    cont="1"
    for file in $files[@]; do
        printf "%s%s$cont%s $file\n" "$BLD" "$CGR" "$CNC"
    done
    echo ""
    read -rp "Choose an option: [client.conf] " opt
    qrencode -t ansiutf8 < "$dir/$opt"
}

if [ $EUID -ne 0 ]; then
    clear
    printf "[ %s%sERROR%s ] Execute the script as root" "$BLD" "$CRE" "$CNC"
    exit 1
fi

while true; do
    printf "%s%s1.%s Install Wireguard server\n
%s%s2.%s Add a new client\n
%s%s3.%s Generate a QR\n
%s%s4.%s Exit\n\n" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC"
    read -rp "Choose an option: [1-4] " opt
    case $opt in
        1) full_install;;
        2) new_client;;
        3) generate_qr;;
        4) exit;;
    esac
done
