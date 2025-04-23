#!/bin/bash

ALLOWED_OPTIONS="log_level type name webapi_url webapi_key server_type node_id soga_key routes_url cert_domain cert_mode dns_provider DNS_CF_Email DNS_CF_Key cert_url listen dns force_close_ssl block_list_url redis_enable redis_addr redis_password redis_db conn_limit_expiry dy_limit_enable dy_limit_duration dy_limit_trigger_time dy_limit_trigger_speed dy_limit_speed dy_limit_time dy_limit_white_user_id user_conn_limit user_tcp_limit auto_out_ip"
REQUIRED_OPTIONS="log_level type name webapi_url webapi_key server_type soga_key node_id"

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
		"log_level=$log_level" \
		"type=$type" \
		"api=webapi" \
		"webapi_url=$webapi_url" \
		"webapi_key=$webapi_key" \
		"soga_key=$soga_key" \
		"server_type=$server_type" \
		"node_id=$node_id" \
		"check_interval=15" \
		"proxy_protocol=true" \
		"udp_proxy_protocol=true" \
		"sniff_redirect=true" \
		"detect_packet=true" \
		"forbidden_bit_torrent=true" \
		"force_vmess_aead=true" \
		"geo_update_enable=true" \
		"ss_invalid_access_enable=true" \
		"ss_invalid_access_count=5" \
		"ss_invalid_access_duration=30" \
		"ss_invalid_access_forbidden_time=120" \
		"vmess_aead_invalid_access_enable=true" \
		"vmess_aead_invalid_access_count=5" \
		"vmess_aead_invalid_access_duration=30" \
		"vmess_aead_invalid_access_forbidden_time=120"
		>.env
  
	if [ ! -z "$listen" ]; then
		sed -i "/^listen=/d" .env
		echo "listen=$listen" >>.env
	fi

	if [ ! -z "$dns" ]; then
		sed -i "/^dns=/d" .env
		echo "dns=$dns" >>.env
	fi

	if [ ! -z "$auto_out_ip" ]; then
		sed -i "/^auto_out_ip=/d" .env
		echo "auto_out_ip=$auto_out_ip" >>.env
	fi

	if [ ! -z "$force_close_ssl" ]; then
		sed -i "/^force_close_ssl=/d" .env
		echo "force_close_ssl=$force_close_ssl" >>.env
	fi

	if [ ! -z "$block_list_url" ]; then
		sed -i "/^block_list_url=/d" .env
		echo "block_list_url=$block_list_url" >>.env
	fi

	if [ ! -z "$cert_domain" ]; then
		sed -i "/^cert_domain=/d" .env
		echo "cert_domain=$cert_domain" >>.env
	fi
	if [ ! -z "$cert_mode" ]; then
		sed -i "/^cert_mode=/d" .env
		echo "cert_mode=$cert_mode" >>.env
	fi
	if [ ! -z "$dns_provider" ]; then
		sed -i "/^dns_provider=/d" .env
		echo "dns_provider=$dns_provider" >>.env
	fi
	if [ ! -z "$DNS_CF_Email" ]; then
		sed -i "/^DNS_CF_Email=/d" .env
		echo "DNS_CF_Email=$DNS_CF_Email" >>.env
	fi
	if [ ! -z "$DNS_CF_Key" ]; then
		sed -i "/^DNS_CF_Key=/d" .env
		echo "DNS_CF_Key=$DNS_CF_Key" >>.env
	fi

	if [ ! -z "$redis_enable" ]; then
		sed -i "/^redis_enable=/d" .env
		echo "redis_enable=$redis_enable" >>.env
	fi

	if [ ! -z "$redis_addr" ]; then
		sed -i "/^redis_addr=/d" .env
		echo "redis_addr=$redis_addr" >>.env
	fi

	if [ ! -z "$redis_password" ]; then
		sed -i "/^redis_password=/d" .env
		echo "redis_password=$redis_password" >>.env
	fi

	if [ ! -z "$redis_db" ]; then
		sed -i "/^redis_db=/d" .env
		echo "redis_db=$redis_db" >>.env
	fi

	if [ ! -z "$conn_limit_expiry" ]; then
		sed -i "/^conn_limit_expiry=/d" .env
		echo "conn_limit_expiry=$conn_limit_expiry" >>.env
	fi

	if [ ! -z "$dy_limit_enable" ]; then
		sed -i "/^dy_limit_enable=/d" .env
		echo "dy_limit_enable=$dy_limit_enable" >>.env
	fi

	if [ ! -z "$dy_limit_duration" ]; then
		sed -i "/^dy_limit_duration=/d" .env
		echo "dy_limit_duration=$dy_limit_duration" >>.env
	fi

	if [ ! -z "$dy_limit_trigger_time" ]; then
		sed -i "/^dy_limit_trigger_time=/d" .env
		echo "dy_limit_trigger_time=$dy_limit_trigger_time" >>.env
	fi

	if [ ! -z "$dy_limit_trigger_speed" ]; then
		sed -i "/^dy_limit_trigger_speed=/d" .env
		echo "dy_limit_trigger_speed=$dy_limit_trigger_speed" >>.env
	fi

	if [ ! -z "$dy_limit_speed" ]; then
		sed -i "/^dy_limit_speed=/d" .env
		echo "dy_limit_speed=$dy_limit_speed" >>.env
	fi

	if [ ! -z "$dy_limit_time" ]; then
		sed -i "/^dy_limit_time=/d" .env
		echo "dy_limit_time=$dy_limit_time" >>.env
	fi

	if [ ! -z "$dy_limit_white_user_id" ]; then
		sed -i "/^dy_limit_white_user_id=/d" .env
		echo "dy_limit_white_user_id=$dy_limit_white_user_id" >>.env
	fi

	if [ ! -z "$user_conn_limit" ]; then
		sed -i "/^user_conn_limit=/d" .env
		echo "user_conn_limit=$user_conn_limit" >>.env
	fi

	if [ ! -z "$user_tcp_limit" ]; then
		sed -i "/^user_tcp_limit=/d" .env
		echo "user_tcp_limit=$user_tcp_limit" >>.env
	fi

	if [ ! -z "$dns_provider" ]; then
		sed -i "/^dns_provider=/d" .env
		echo "dns_provider=$dns_provider" >>.env
	fi

	if [ ! -z "$cert_url" ]; then
		domain=$(basename "$cert_url")
		cert_filename=${cert_filename%.crt}
		key_filename=${cert_filename%.key}
		curl -fsSL "${cert_url}.crt" -o "/opt/$name/config/cert.crt"
		curl -fsSL "${cert_url}.key" -o "/opt/$name/config/cert.key"
        sed -i "/^cert_file=/d" .env
        sed -i "/^key_file=/d" .env
		echo "cert_file=/etc/soga/cert.crt" >>.env
		echo "key_file=/etc/soga/cert.key" >>.env
	fi

	if [ ! -z "$routes_url" ]; then
		echo "下载 routes.toml 文件..."
		curl -fsSL "$routes_url" -o /opt/$name/config/routes.toml
	fi

	printf "%s\n" \
	  "---" \
	  "services:" \
	  "  ${name}:" \
	  "    image: vaxilu/soga:latest" \
	  "    container_name: ${name}" \
	  "    restart: always" \
	  "    network_mode: host" \
	  "    env_file:" \
	  "      - .env" \
	  "    volumes:" \
	  "      - \"./config:/etc/soga/\"" > docker-compose.yaml
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
