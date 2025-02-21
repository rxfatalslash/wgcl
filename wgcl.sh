#!/bin/bash
# author: rxfatalslash

CRE=$(tput setaf 1)
CGR=$(tput setaf 2)
BLD=$(tput bold)
CNC=$(tput sgr0)

# logo
logo () {
    printf '%s%s                       _    
                      | |   
   __      ____ _  ___| |   
   \ \ /\ / / _` |/ __| |   
    \ V  V / (_| | (__| |   
     \_/\_/ \__, |\___|_|   
             __/ |          
            |___/           
    %s\n' "$BLD" "$CGR" "$CNC"
}

declare -g ip=""
declare -g dns=""

full_install() {
    distro=$(grep "^ID=" /etc/os-release | cut -d '=' -f2 | sed -e 's/"//g')
    id=$(grep "^ID_LIKE=" /etc/os-release | cut -d '=' -f2 | sed -e 's/"//g')
    id=${id:-$distro}
    clear
    case $id in
        debian*)
            printf "%s%sDebian based system detected%s\n" "$CBL" "$CGR" "$CNC"
            if ! dpkg -l | awk '/wireguard/{found=1} END{exit !found}'; then
                apt-get install -y wireguard
            fi

            if ! dpkg -l | grep -iq "qrencode"; then
                apt-get install -y qrencode
            fi
        ;;
        arch*)
            printf "%s%sArch based system detected%s\n" "$CBL" "$CGR" "$CNC"
            if ! pacman -Qs wireguard-tools > /dev/null; then
                pacman -Sy wireguard-tools --noconfirm
            fi

            if ! pacman -Qs qrencode > /dev/null; then
                pacman -Sy qrencode --noconfirm
            fi
        ;;
        fedora*)
            printf "%s%sFedora based system detected%s\n" "$CBL" "$CGR" "$CNC"
            if ! rpm -qi wireguard-tools > /dev/null; then
                dnf install -y wireguard-tools
            fi

            if ! rpm -qi qrencode > /dev/null; then
                dnf install -y qrencode
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
    echo ""
    read -rp "$(printf "What IP do you want for the Wireguard server?: [%s%s10.0.0.1%s] " "$BLD" "$CGR" "$CNC")" ip

    if [ -z $ip ]; then
        ip="10.0.0.1"
    fi

    while true; do
        echo ""
        printf "%s%s1.%s Default port [%s%s51820%s]\n
%s%s2.%s Custom port\n\n" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC"
        read -rp "$(printf "Choose an option: [%s%s1%s-%s%s2%s] " "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC")" opt
        case $opt in
            1)
                port="51820"
                break
            ;;
            2)
                clear
                read -rp "What port do you want for the Wireguard server?: " port
                if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
                    printf "[ %s%sERROR%s ] Choose a valid port" "$BLD" "$CRE" "$CNC"
                fi
                break
            ;;
            *)
                clear
                printf "[ %s%sERROR%s ] Choose a valid option: [1-2]" "$BLD" "$CRE" "$CNC"
            ;;
        esac
    done

    echo -e "[Interface]
Address = $ip/24
ListenPort = $port
PrivateKey = $pkey
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $int -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $int -j MASQUERADE
SaveConfig = false" > /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf /etc/wireguard/keys/server.key

    wg-quick up wg0
    systemctl enable wg-quick@wg0.service
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
    sysctl -p
}

new_client() {
    if [ ! -d /etc/wireguard ]; then
        clear
        printf "[ %s%sERROR%s ] Wireguard is not installed" "$BLD" "$CRE" "$CNC"
        exit
    fi

    if [ ! -d /etc/wireguard/clients ] ; then
        mkdir -p /etc/wireguard/clients
    fi

    while true; do
        read -rp "What's the name of the device?: " client
        if [ ! -z $client ]; then
            break
        else
            clear
            printf "[ %s%sERROR%s ] Introduce un device name" "$BLD" "$CRE" "$CNC"
        fi
    done

    wg genkey > /etc/wireguard/clients/"$client".key
    cat /etc/wireguard/clients/"$client".key | wg pubkey > /etc/wireguard/clients/"$client".key.pub

    priv_key=$(cat /etc/wireguard/clients/"$client".key)
    pub_server_key=$(cat /etc/wireguard/keys/server.key.pub)
    pub_key=$(cat /etc/wireguard/clients/"$client".key.pub)
    pub_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
    port=$(sudo grep "^ListenPort" /etc/wireguard/wg0.conf | cut -d '=' -f2)
    port=${port// /}

    clear
    read -rp "What is the client's IP: " client_ip
    while true; do
        clear
        printf "%s%s1.%s Cloudflare\n
%s%s2.%s Google\n
%s%s3.%s Custom\n\n" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC"
        read -rp "$(printf "Choose a DNS option: [1-3] " "$BLD" "$CGR" "$CNC")" opt
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
                read -rp "Enter a custom DNS: (Add a comma between both to add 2 DNS)" dns
                break
            ;;
            *)
                clear
                printf "[ %s%sERROR%s ] Choose a valid option: [1-3] "opt
            ;;
        esac
    done

    echo -e "[Interface]
PrivateKey = $priv_key
Address = $client_ip/24
DNS = $dns

[Peer]
PublicKey = $pub_server_key
Endpoint = $pub_ip:$port
AllowedIPs = 0.0.0.0/0
PersistentKeepAlive = 25" > /etc/wireguard/clients/"$client".conf

    # wg set wg0 peer $pub_key allowed-ips $client_ip
    echo -e "
[Peer]
PublicKey = $pub_key
AllowedIPs = $client_ip/32" >> /etc/wireguard/wg0.conf
    clear
}

revoke_client() {
    if [ ! -d /etc/wireguard ]; then
        clear
        printf "[ %s%sERROR%s ] Wireguard is not installed" "$BLD" "$CRE" "$CNC"
        exit
    fi

    if [ ! -d /etc/wireguard/clients ]; then
        clear
        printf "[ %s%sERROR%s ] There are no clients" "$BLD" "$CRE" "$CNC"
        exit
    fi

    clear
    dir="/etc/wireguard/clients"
    files=$(ls $dir | cut -d. -f1 | sort | uniq)

    cont=1
    if [ -z "$(ls -A /etc/wireguard/clients 2>/dev/null)" ]; then
        printf "[ %s%sERROR%s ] There are no clients" "$BLD" "$CRE" "$CNC"
        exit
    else
        for file in $files; do
            printf "%s%s%d.%s $file\n" "$BLD" "$CGR" "$cont" "$CNC"
            ((cont++))
        done
        echo ""
        read -rp "Choose an option: [client] " opt
        key=$(cat /etc/wireguard/clients/$opt.key.pub)
        wg set wg0 peer $key remove
        rm /etc/wireguard/clients/$opt.*
    fi
}

remove_wireguard() {
    # distro=$(grep "^NAME=" /etc/os-release | cut -d '=' -f2 | sed -e 's/"//g')
    id=$(grep "^ID_LIKE=" /etc/os-release | cut -d '=' -f2 | sed -e 's/"//g')
    clear
    case $id in
        debian*)
            if dpkg -l | grep -iq "wireguard" > /dev/null; then
                apt-get remove -y wireguard
            else
                printf "[ %s%sERROR%s ] Wireguard is not installed" "$BLD" "$CRE" "$CNC"
                exit
            fi
        ;;
        arch*)
            if pacman -Qs wireguard-tools > /dev/null; then
                pacman -R wireguard-tools --noconfirm
            else
                printf "[ %s%sERROR%s ] Wireguard is not installed" "$BLD" "$CRE" "$CNC"
                exit
            fi
        ;;
        fedora*)
            if rpm -qi wireguard-tools > /dev/null; then
                dnf remove -y wireguard-tools
            else
                printf "[ %s%sERROR%s ] Wireguard is not installed" "$BLD" "$CRE" "$CNC"
                exit
            fi
        ;;
    esac

    wg_dev=$(ls /etc/wireguard/*.conf 2>/dev/null | head -n 1 | xargs -n1 basename | cut -d '.' -f1)
    if [ -n "$wg_dev" ]; then
        ip link delete "$wg_dev"
    fi
    rm -rf /etc/wireguard
}

generate_qr() {
    if [ ! -d /etc/wireguard ]; then
        clear
        printf "[ %s%sERROR%s ] Wireguard is not installed" "$BLD" "$CRE" "$CNC"
        exit
    fi

    if [ ! -d /etc/wireguard/clients ]; then
        clear
        printf "[ %s%sERROR%s ] There are no clients" "$BLD" "$CRE" "$CNC"
        exit
    fi

    clear
    dir="/etc/wireguard/clients"
    files=$(ls $dir | cut -d. -f1 | sort | uniq)

    cont=1
    if [ -z "$(ls -A /etc/wireguard/clients 2>/dev/null)" ]; then
        printf "[ %s%sERROR%s ] There are no clients" "$BLD" "$CRE" "$CNC"
        exit
    else
        for file in $files; do
            printf "%s%s%d.%s $file\n" "$BLD" "$CGR" "$cont" "$CNC"
            ((cont++))
        done
        echo ""
        read -rp "Choose an option: [client] " opt
        qrencode -t ansiutf8 < "$dir/$opt.conf"
    fi
}

if [ $EUID -ne 0 ]; then
    clear
    printf "[ %s%sERROR%s ] Execute the script as root" "$BLD" "$CRE" "$CNC"
    exit 1
fi

while true; do
    logo
    printf "%s%s1.%s Install Wireguard server\n
%s%s2.%s Add a new client\n
%s%s3.%s Revoke a client\n
%s%s4.%s Generate a QR\n
%s%s5.%s Remove Wireguard\n
%s%s6.%s Exit\n\n" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC"
    read -rp "$(printf "Choose an option: [%s%s1%s-%s%s6%s] " "$BLD" "$CGR" "$CNC" "$BLD" "$CGR" "$CNC")" opt
    case $opt in
        1) full_install;;
        2) new_client;;
        3) revoke_client;;
        4) generate_qr;;
        5) remove_wireguard;;
        6) exit;;
        *)
            clear
            printf "[ %s%sERROR%s ] Choose a valid option: [1-6]\n" "$BLD" "$CRE" "$CNC"
        ;;
    esac
done
