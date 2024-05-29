#!/bin/bash

clear

echo -e "\e[33mRunning this script will remove the older installation and directories of Marzban-node for the specified panel!!\e[0m\n"

read -rp "Do you want to continue? (Y/n): " consent

case "$consent" in
    [Yy]* ) 
        echo -e "\e[32mProceeding with the script...\e[0m"
        ;;
    [Nn]* ) 
        echo -e "\e[31mScript terminated by the user.\e[0m"
        exit 0
        ;;
    * ) 
        echo -e "\e[31mInvalid input. Script will exit.\e[0m"
        exit 1
        ;;
esac

clear

read -rp "Set a nickname for your panel: " panel

panel=${panel:-node$(openssl rand -hex 1)}

clear
echo -e "\e[32mPanel set to: $panel\e[0m"
echo "Removing existing directories and files..."

rm -rf "$HOME/$panel" &> /dev/null
sudo rm -rf /var/lib/marzban-node/$panel.pem &> /dev/null
sudo rm -rf /var/lib/marzban-node/$panel-core &> /dev/null

echo "Installing necessary packages..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install curl socat git wget unzip -y

trap 'echo "Ctrl+C was pressed but the script will continue."' SIGINT

curl -fsSL https://get.docker.com | sh || {
    echo -e "\e[31mSomething went wrong! Did you interrupt the Docker update? No problem - Are you trying to install Docker on an IR server? Try setting DNS.\e[0m"
}

trap - SIGINT

echo "Checking if Docker is installed..."
if ! command -v docker &> /dev/null; then
    echo -e "\e[31mDocker could not be found, please install Docker.\e[0m"
    exit 1
fi

clear

architecture() {
    local arch
    case "$(uname -m)" in
        'i386' | 'i686')
            arch='32'
            ;;
        'amd64' | 'x86_64')
            arch='64'
            ;;
        'armv5tel')
            arch='arm32-v5'
            ;;
        'armv6l')
            arch='arm32-v6'
            grep Features /proc/cpuinfo | grep -qw 'vfp' || arch='arm32-v5'
            ;;
        'armv7' | 'armv7l')
            arch='arm32-v7a'
            grep Features /proc/cpuinfo | grep -qw 'vfp' || arch='arm32-v5'
            ;;
        'armv8' | 'aarch64')
            arch='arm64-v8a'
            ;;
        'mips')
            arch='mips32'
            ;;
        'mipsle')
            arch='mips32le'
            ;;
        'mips64')
            arch='mips64'
            lscpu | grep -q "Little Endian" && arch='mips64le'
            ;;
        'mips64le')
            arch='mips64le'
            ;;
        'ppc64')
            arch='ppc64'
            ;;
        'ppc64le')
            arch='ppc64le'
            ;;
        'riscv64')
            arch='riscv64'
            ;;
        's390x')
            arch='s390x'
            ;;
        *)
            echo -e "\e[31mError: The architecture is not supported.\e[0m"
            return 1
            ;;
    esac
    echo "$arch"
}

arch=$(architecture)
if [ $? -ne 0 ]; then
    exit 1
fi

sudo mkdir -p /var/lib/marzban-node
cd "/var/lib/marzban-node/" || {
    echo -e "\e[31mFailed to change directory to /var/lib/marzban-node/.\e[0m"
    exit 1
}

clear

read -rp "Which version of Xray-core do you want? (example: 1.8.8) (leave blank for latest): " version
version=${version:-latest}

if [[ $version == "latest" ]]; then
    wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$arch.zip"
else
    wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v$version/Xray-linux-$arch.zip"
fi

if unzip xray.zip; then
    rm xray.zip
    rm -v geosite.dat geoip.dat LICENSE README.md
    mv -v xray "$panel-core"
else
    echo -e "\e[31mFailed to unzip xray.zip.\e[0m"
    exit 1
fi

echo -e "\e[32mSuccess! Now get ready for setup.\e[0m"
clear

while true; do
    read -rp "Enter the SERVICE PORT value (default 62050): " service
    service=${service:-62050}
    if [[ $service =~ ^[0-9]+$ ]] && [ $service -ge 1 ] && [ $service -le 65535 ]; then
        break
    else
        echo -e "\e[31mInvalid input. Please enter a valid port number between 1 and 65535.\e[0m"
    fi
done

while true; do
    read -rp "Enter the XRAY API PORT value (default 62051): " api
    api=${api:-62051}
    if [[ $api =~ ^[0-9]+$ ]] && [ $api -ge 1 ] && [ $api -le 65535 ]; then
        break
    else
        echo -e "\e[31mInvalid input. Please enter a valid port number between 1 and 65535.\e[0m"
    fi
done

sudo mkdir -p "$HOME/$panel"

ENV="$HOME/$panel/.env"
DOCKER="$HOME/$panel/docker-compose.yml"

cat << EOF > "$ENV"
SERVICE_PORT=$service
XRAY_API_PORT=$api
XRAY_EXECUTABLE_PATH=/var/lib/marzban-node/$panel-core
SSL_CLIENT_CERT_FILE=/var/lib/marzban-node/$panel.pem
SERVICE_PROTOCOL=rest
EOF

echo -e "\e[32m.env file has been created successfully.\e[0m"

cat << 'EOF' > "$DOCKER"
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    env_file: .env
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
EOF

echo -e "\e[32mdocker-compose.yml has been created successfully.\e[0m"

echo "Please paste the content of the Client Certificate, press ENTER on a new line when finished:"

cert=""
while IFS= read -r line; do
    if [[ -z $line ]]; then
        break
    fi
    cert+="$line\n"
done

echo -e "$cert" | sudo tee /var/lib/marzban-node/$panel.pem > /dev/null
echo -e "\e[32mCertificate is ready, starting the container...\e[0m"
cd "$HOME/$panel" || { echo "Something went wrong! couldnt enter $panel directory"; exit 1;}
docker compose up -d --remove-orphans
