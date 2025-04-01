#!/bin/bash

ALLOWED_OPTIONS="name webapi_url webapi_key server_type node_id soga_key routes_url cert_domain cert_mode dns_provider DNS_CF_Email DNS_CF_Key cert_url listen dns force_close_ssl"
REQUIRED_OPTIONS="name webapi_url webapi_key server_type soga_key node_id"

usage() {
    echo "用法: $0 [选项]"
    echo "允许的选项:"
    for opt in $ALLOWED_OPTIONS; do
        echo "  -$opt <value>"
    done
    echo "必填的选项:"
    for opt in $REQUIRED_OPTIONS; do
        echo "  -$opt <value>"
    done
    exit 1
}

parse_options() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -*)
                opt="${1#-}"
                valid=0
                for allowed in $ALLOWED_OPTIONS; do
                    if [ "$opt" = "$allowed" ]; then
                        valid=1
                        break
                    fi
                done
                if [ "$valid" -eq 0 ]; then
                    echo "未知选项: $1"
                    usage
                fi

                shift
                if [ $# -eq 0 ]; then
                    echo "选项 -$opt 缺少参数"
                    usage
                fi
                eval "$opt=\$1"
                ;;
            *)
                echo "无法识别的参数: $1"
                usage
                ;;
        esac
        shift
    done
    for req in $REQUIRED_OPTIONS; do
        eval "value=\$$req"
        if [ -z "$value" ]; then
            echo "缺少必填选项: -$req"
            usage
        fi
    done
}


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

DeplaySoga() {
    mkdir -p /opt/$name
    mkdir -p /opt/$name/config
    cd /opt/$name
    printf "%s\n" \
    "log_level=debug" \
    "type=v2board" \
    "api=webapi" \
    "webapi_url=$webapi_url" \
    "webapi_key=$webapi_key" \
    "soga_key=$soga_key" \
    "server_type=$server_type" \
    "node_id=$node_id" \
    "listen=$listen" \
    "auto_out_ip=true" \
    "check_interval=15" \
    "default_dns=$dns" \
    "proxy_protocol=true" \
    "udp_proxy_protocol=true" \
    "sniff_redirect=true" \
    "detect_packet=true" \
    "forbidden_bit_torrent=true" \
    "force_vmess_aead=true" \
    "force_close_ssl=$force_close_ssl" \
    "geo_update_enable=true" \
    "ss_invalid_access_enable=true" \
    "ss_invalid_access_count=5" \
    "ss_invalid_access_duration=30" \
    "ss_invalid_access_forbidden_time=120" \
    "vmess_aead_invalid_access_enable=true" \
    "vmess_aead_invalid_access_count=5" \
    "vmess_aead_invalid_access_duration=30" \
    "vmess_aead_invalid_access_forbidden_time=120" \
    "dy_limit_enable=true" \
    "dy_limit_trigger_time=300" \
    "dy_limit_trigger_speed=300" \
    "dy_limit_speed=100" \
    "dy_limit_time=1800" \
    "block_list_url=https://raw.githubusercontent.com/monatrople/rulelist/refs/heads/main/blockList" \
    > .env


    if [ -z "$listen" ]; then
      sed -i '/^listen=$/d' .env
    fi
    if [ -z "$force_close_ssl" ]; then
      sed -i '/^force_close_ssl=$/d' .env
    fi
    if [ -z "$dns" ]; then
      sed -i '/^default_dns=$/d' .env
    fi
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
    echo "下载 geoip.dat,geosite.dat 文件..."
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

parse_options "$@"
InstallDocker
DeplaySoga
