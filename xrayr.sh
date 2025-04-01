#!/bin/sh

ALLOWED_OPTIONS="name panel_type api_host api_key node_id node_type proxy_protocol dns cert_mode cert_domain cert_file_url key_file_url dns_provider email CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY_FILE listenip inbound_url outbound_url route_url"
REQUIRED_OPTIONS="name panel_type api_host api_key node_id node_type proxy_protocol"

DEPLOY_BASEDIR="/opt"

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

install_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 未安装，尝试自动安装..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            apt-get install -y "$2"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "$2"
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "$2"
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Syu --noconfirm "$2"
        elif command -v zypper >/dev/null 2>&1; then
            zypper refresh
            zypper install -y "$2"
        else
            echo "未找到支持的包管理器，请手动安装 $1。"
            return 1
        fi
    fi
}

install_docker() {
    # 检查 Docker 是否已安装
    if command -v docker >/dev/null 2>&1; then
        echo "Docker 已安装。"
    else
        echo "检测包管理器..."
        if command -v apt-get >/dev/null 2>&1; then
            echo "检测到 apt-get，适用于 Debian/Ubuntu 系统。"
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
            if [ -f /etc/os-release ]; then
                . /etc/os-release
            fi
            curl -fsSL "https://download.docker.com/linux/$ID/gpg" | apt-key add -
            if [ -n "$VERSION_CODENAME" ]; then
                codename="$VERSION_CODENAME"
            else
                codename=$(lsb_release -cs)
            fi
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$ID $codename stable"
            apt-get update
            apt-get install -y docker-ce docker-compose-plugin

        elif command -v yum >/dev/null 2>&1; then
            echo "检测到 yum，适用于 CentOS/RHEL 系统。"
            yum install -y yum-utils device-mapper-persistent-data lvm2
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-compose-plugin
            systemctl start docker
            systemctl enable docker

        elif command -v dnf >/dev/null 2>&1; then
            echo "检测到 dnf，适用于 Fedora/CentOS 系统。"
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-compose-plugin
            systemctl start docker
            systemctl enable docker

        elif command -v pacman >/dev/null 2>&1; then
            echo "检测到 pacman，适用于 Arch Linux 系统。"
            pacman -Syu --noconfirm docker docker-compose
            systemctl start docker
            systemctl enable docker
        else
            echo "未找到支持的包管理器，请手动安装 Docker。"
            return 1
        fi

        if command -v docker >/dev/null 2>&1; then
            echo "Docker 安装成功。"
        else
            echo "Docker 安装失败。"
            return 1
        fi
    fi
}


install_yq() {
    if command -v yq >/dev/null 2>&1; then
        echo "yq 已安装。"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        install_dependency curl curl
        install_dependency wget wget
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            echo "依赖 curl 或 wget 安装失败，请手动安装其中之一。"
            return 1
        fi
    fi
    echo "未检测到 yq，开始安装..."
    if command -v curl >/dev/null 2>&1; then
        LATEST_YQ_VERSION=$(curl --silent "https://api.github.com/repos/mikefarah/yq/releases/latest" \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    elif command -v wget >/dev/null 2>&1; then
        LATEST_YQ_VERSION=$(wget -q -O - "https://api.github.com/repos/mikefarah/yq/releases/latest" \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi

    if [ -z "$LATEST_YQ_VERSION" ]; then
        echo "无法获取最新的 yq 版本。"
        return 1
    fi
    echo "检测到最新 yq 版本：$LATEST_YQ_VERSION"
    YQ_URL="https://github.com/mikefarah/yq/releases/download/${LATEST_YQ_VERSION}/yq_linux_amd64"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o /usr/bin/yq "$YQ_URL" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -O /usr/bin/yq "$YQ_URL" >/dev/null 2>&1
    fi

    chmod +x /usr/bin/yq

    # 检查 yq 是否安装成功
    if command -v yq >/dev/null 2>&1; then
        echo "yq 安装成功。"
        return 0
    else
        echo "yq 安装失败。"
        return 1
    fi
}

deploy_xrayr(){
	if [ -z "$listenip" ]; then
		listenip="0.0.0.0"
	fi
 	rm -rf $DEPLOY_BASEDIR/$name
	mkdir -p $DEPLOY_BASEDIR/$name/config
	mkdir -p $DEPLOY_BASEDIR/$name/cert
	mkdir -p $DEPLOY_BASEDIR/$name/log
	cd $DEPLOY_BASEDIR/$name
	printf "%s\n"                                   \
	"services:"                                     \
	"  XrayR:"                                      \
	"    image: daley7292/xrayr:master" \
	"    container_name: $name"                     \
	"    hostname: XrayR"                           \
	"    restart: always"                           \
	"    network_mode: host"                        \
	"    volumes:"                                  \
	"      - ./config:/etc/XrayR/"                  \
	"      - ./cert:/etc/cert/"                     \
	"      - ./log:/log"                            \
	> docker-compose.yml
 
	printf "%s\n"                                   \
	"Log:"                                          \
	"  Level: error"                                \
	""                                              \
	"DnsConfigPath: /etc/XrayR/dns.json"            \
	"RouteConfigPath: /etc/XrayR/route.json"        \
	"InboundConfigPath: /etc/XrayR/inbound.json"    \
	"OutboundConfigPath: /etc/XrayR/outbound.json"  \
	""                                              \
	"ConnetionConfig:"                              \
	"  Handshake: 4"                                \
	"  ConnIdle: 30"                                \
	"  UplinkOnly: 2"                               \
	"  DownlinkOnly: 4"                             \
	"  BufferSize: 64"                              \
	""                                              \
	"Nodes:"                                        \
	> config/config.yaml

	IFS=',' read -r -a node_ids <<< "$node_id"
	for i in "${!node_ids[@]}"; do
        node_index=$((i+1))
        printf "%s\n"                                   \
        "  - PanelType: \"$panel_type\""                \
        "    ApiConfig:"                                \
        "      ApiHost: \"$api_host\""                  \
        "      ApiKey: \"$api_key\""                    \
        "      NodeID: ${node_ids[$i]}"                 \
        "      NodeType: $node_type"                    \
        "      Timeout: 60"                             \
        "      RuleListPath: /etc/XrayR/rulelist"       \
        "    ControllerConfig:"                         \
        "      ListenIP: $listenip"                     \
        "      SendIP: $listenip"                       \
        "      UpdatePeriodic: 60"                      \
        "      EnableDNS: true"                         \
        "      DNSType: UseIPv4"                        \
        "      EnableProxyProtocol: $proxy_protocol"    \
	"      AutoSpeedLimitConfig:"                   \
        "        Limit: 200"                            \
	"        WarnTimes: 300"                        \
        "        LimitSpeed: 100"                       \
	"        LimitDuration: 1500"                   \
        >> config/config.yaml
	done
 
	printf "%s\n"                                   \
	"{"                                             \
	"  \"servers\": ["                              \
	"    \"localhost\""                             \
	"  ],"                                          \
	"  \"tag\": \"dns_inbound\""                    \
	"}"                                             \
	> config/dns.json
	printf "%s\n"                                   \
	"{"                                             \
	"  \"domainStrategy\": \"IPOnDemand\","         \
	"  \"rules\": ["                                \
	"    {"                                         \
	"      \"type\": \"field\","                    \
	"      \"outboundTag\": \"block\","             \
	"      \"protocol\": ["                         \
	"        \"bittorrent\""                        \
	"      ]"                                       \
	"    }"                                         \
	"  ]"                                           \
	"}"                                             \
	> config/route.json
	printf "%s\n"                                   \
	"[]"                                            \
	> config/inbound.json
	printf "%s\n"                                   \
	"["                                             \
	"  {"                                           \
	"    \"tag\": \"IPv4_out\","                    \
	"    \"protocol\": \"freedom\""                 \
	"  },"                                          \
	"  {"                                           \
	"    \"tag\": \"IPv6_out\","                    \
	"    \"protocol\": \"freedom\","                \
	"    \"settings\": {"                           \
	"      \"domainStrategy\": \"UseIPv6\""         \
	"    }"                                         \
	"  },"                                          \
	"  {"                                           \
	"    \"tag\": \"block\","                       \
	"    \"protocol\": \"blackhole\""               \
	"  }"                                           \
	"]"                                             \
	> config/outbound.json
	printf "%s\n"                                   \
	"360"                                           \
	> config/rulelist

	if [ -n "$dns" ] && printf '%s' "$dns" | grep -Eq '^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'; then
		yq eval ".servers = [\"$dns\"]" -i config/dns.json
	else
 		dns="localhost"
		yq eval ".servers = [\"$dns\"]" -i config/dns.json
	fi
	if [ -n "$cert_mode" ]; then
		yq eval ".Nodes[].ControllerConfig.CertConfig.CertMode = \"$cert_mode\"" -i config/config.yaml
	fi
	if [ -n "$cert_domain" ]; then
		yq eval ".Nodes[].ControllerConfig.CertConfig.CertDomain = \"$cert_domain\"" -i config/config.yaml
	fi
	if [ -n "$dns_provider" ]; then
		yq eval ".Nodes[].ControllerConfig.CertConfig.Provider = \"$dns_provider\"" -i config/config.yaml
	fi
	if [ -n "$email" ]; then
		yq eval ".Nodes[].ControllerConfig.CertConfig.Email = \"$email\"" -i config/config.yaml
	fi
	if [ -n "$CLOUDFLARE_EMAIL" ] && [ -n "$CLOUDFLARE_API_KEY_FILE" ]; then
		yq eval ".Nodes[].ControllerConfig.CertConfig.DNSEnv.CLOUDFLARE_EMAIL = \"$CLOUDFLARE_EMAIL\"" -i config/config.yaml
		yq eval ".Nodes[].ControllerConfig.CertConfig.DNSEnv.CLOUDFLARE_API_KEY_FILE = \"$CLOUDFLARE_API_KEY_FILE\"" -i config/config.yaml
	fi
	if [ -n "$cert_file_url" ] && [ -n "$key_file_url" ]; then
		wget -q $cert_file_url -O cert/ssl.crt >/dev/null 2>&1
		wget -q $key_file_url -O cert/ssl.key >/dev/null 2>&1
		yq eval ".Nodes[].ControllerConfig.CertConfig.CertFile = \"/etc/cert/ssl.crt\"" -i config/config.yaml
		yq eval ".Nodes[].ControllerConfig.CertConfig.KeyFile = \"/etc/cert/ssl.key\"" -i config/config.yaml
	fi
 	if [ -n "$inbound_url" ]; then
		wget -q $inbound_url -O $DEPLOY_BASEDIR/$name/config/inbound.json >/dev/null 2>&1
	fi
 	if [ -n "$outbound_url" ]; then
		wget -q $outbound_url -O $DEPLOY_BASEDIR/$name/config/outbound.json >/dev/null 2>&1
	fi
  	if [ -n "$route_url" ]; then
		wget -q $route_url -O $DEPLOY_BASEDIR/$name/config/route.json >/dev/null 2>&1
	fi
	wget -q -4 https://github.com/v2fly/geoip/releases/latest/download/geoip.dat -O config/geoip.dat >/dev/null 2>&1
	wget -q -4 https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat -O config/geosite.dat >/dev/null 2>&1
	docker compose down >/dev/null 2>&1
	docker compose up -d
}

parse_options "$@"
install_docker
install_yq
deploy_xrayr
