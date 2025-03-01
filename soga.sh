#!/bin/bash

name=""
webapi_url=""
webapi_key=""
server_type=""
node_id=""
soga_key=""
routes_url=""
cert_domain=""
cert_mode=""
dns_provider=""
DNS_CF_Email=""
DNS_CF_Key=""
cert_url=""
listen=""

# 解析命令行参数
for arg in "$@"
do
    case $arg in
        name=*)
            name="${arg#*=}"
            ;;
        webapi_url=*)
            webapi_url="${arg#*=}"
            ;;
        webapi_key=*)
            webapi_key="${arg#*=}"
            ;;
        server_type=*)
            server_type="${arg#*=}"
            ;;
        node_id=*)
            node_id="${arg#*=}"
            ;;
        soga_key=*)
            soga_key="${arg#*=}"
            ;;
        routes_url=*)
            routes_url="${arg#*=}"
            ;;
        cert_domain=*)
            cert_domain="${arg#*=}"
            ;;
        cert_mode=*)
            cert_mode="${arg#*=}"
            ;;
        dns_provider=*)
            dns_provider="${arg#*=}"
            ;;
        DNS_CF_Email=*)
            DNS_CF_Email="${arg#*=}"
            ;;
        DNS_CF_Key=*)
            DNS_CF_Key="${arg#*=}"
            ;;
        cert_file=*)
            cert_file="${arg#*=}"
            ;;
        key_file=*)
            key_file="${arg#*=}"
            ;;
        cert_url=*)
            cert_url="${arg#*=}"
            ;;
        listen=*)
            listen="${arg#*=}"
            ;;
    esac
done

# 参数验证
if [ -z "$name" ] || [ -z "$webapi_url" ] || [ -z "$webapi_key" ] || [ -z "$server_type" ] || [ -z "$soga_key" ] || [ -z "$node_id" ]; then
    echo "Usage: \$0 name=<name> webapi_url=<webapi_url> webapi_key=<webapi_key> server_type=<server_type> soga_key=<soga_key> node_id=<node_id> [routes_url=<routes_url>] [cert_domain=<cert_domain>] [cert_mode=<cert_mode>] [dns_provider=<dns_provider>] [DNS_CF_Email=<DNS_CF_Email>] [DNS_CF_Key=<DNS_CF_Key>] [cert_file=<cert_file>] [key_file=<key_file>] [cert_url=<cert_url>]"
    exit 1
fi

# 安装 Docker
InstallDocker() {
    if command -v docker &>/dev/null; then
        docker_version=$(docker --version | awk '{print $3}')
        echo -e "Docker 已安装，版本：$docker_version"
    else
        # Detect the OS and install Docker accordingly
        if [ -f /etc/arch-release ]; then
            echo "检测到 Arch Linux 系统，使用 pacman 安装 Docker。"
            pacman -S --noconfirm docker docker-compose
        else
            echo -e "开始安装 Docker..."
            curl -fsSL https://get.docker.com | sh
            rm -rf /opt/containerd
            echo -e "Docker 安装完成。"
        fi
    fi
}

# 部署 Soga 服务
DeplaySoga() {
    mkdir -p /opt/$name
    mkdir -p /opt/$name/config
    cd /opt/$name
    cat <<EOF > .env
log_level=debug
type=v2board
api=webapi
webapi_url=$webapi_url
webapi_key=$webapi_key
soga_key=$soga_key
server_type=$server_type
node_id=$node_id
listen=$listen
auto_out_ip=true
check_interval=15
default_dns=1.1.1.1,1.0.0.1
proxy_protocol=true
udp_proxy_protocol=true
sniff_redirect=true
detect_packet=true
forbidden_bit_torrent=true
force_vmess_aead=true
geo_update_enable=true
ss_invalid_access_enable=true
ss_invalid_access_count=5
ss_invalid_access_duration=30
ss_invalid_access_forbidden_time=120
vmess_aead_invalid_access_enable=true
vmess_aead_invalid_access_count=5
vmess_aead_invalid_access_duration=30
vmess_aead_invalid_access_forbidden_time=120
dy_limit_enable=true
dy_limit_trigger_time=300
dy_limit_trigger_speed=300
dy_limit_speed=100
dy_limit_time=1800
block_list_url=https://raw.githubusercontent.com/monatrople/rulelist/refs/heads/main/blockList
EOF

    if [ -z "$listen" ]; then
      sed -i '/^listen=$/d' your_file.txt
    fi



    # Add optional cert and DNS parameters
    if [ ! -z "$cert_domain" ]; then
        echo "cert_domain=$cert_domain" >> .env
    fi
    if [ ! -z "$cert_mode" ]; then
        echo "cert_mode=$cert_mode" >> .env
    fi
    if [ ! -z "$dns_provider" ]; then
        echo "dns_provider=$dns_provider" >> .env
    fi
    if [ ! -z "$DNS_CF_Email" ]; then
        echo "DNS_CF_Email=$DNS_CF_Email" >> .env
    fi
    if [ ! -z "$DNS_CF_Key" ]; then
        echo "DNS_CF_Key=$DNS_CF_Key" >> .env
    fi

    if [ ! -z "$cert_url" ]; then
        domain=$(basename "$cert_url")
        cert_filename=${cert_filename%.crt}
        key_filename=${cert_filename%.key}
        curl -fsSL "${cert_url}.crt" -o "/opt/$name/config/cert.crt"
        curl -fsSL "${cert_url}.key" -o "/opt/$name/config/cert.key"
        echo "cert_file=/etc/soga/cert.crt" >> .env
        echo "key_file=/etc/soga/cert.key" >> .env
    fi

    # 下载必要的规则文件
    wget -q https://github.com/v2fly/geoip/releases/latest/download/geoip.dat -O config/geoip.dat
    wget -q https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat -O config/geosite.dat

    if [ ! -z "$routes_url" ]; then
        echo "下载 routes.toml 文件..."
        curl -fsSL "$routes_url" -o /opt/$name/config/routes.toml
    fi

    cat <<EOF > docker-compose.yaml
---
services:
  ${name}:
    image: vaxilu/soga:latest
    container_name: ${name}
    restart: always
    network_mode: host
    dns:
      - 1.1.1.1
      - 1.0.0.1
    env_file:
      - .env
    volumes:
      - "./config:/etc/soga/"
EOF

    if command -v docker-compose &>/dev/null; then
        docker-compose up -d --pull always
    else
        docker compose up -d --pull always
    fi
    docker restart $name
}

# 执行安装、优化和部署函数
InstallDocker
DeplaySoga
