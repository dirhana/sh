ALLOWED_OPTIONS="start_index end_index name panel_type api_host api_key node_id node_type proxy_protocol dns cert_mode cert_domain cert_file_url key_file_url dns_provider email CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY_FILE listenip inbound_url outbound_url route_url"
REQUIRED_OPTIONS=""
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
parse_options "$@"
index=0
ip_list=($(ip -4 addr show | awk '/inet / {print $2}' | cut -d'/' -f1 | grep -vE '^(127\.|172\.(1[6-9]|2[0-9]|3[0-1])|169\.254|^0\.|^255\.)'))
if [[ -n "$start_index" && -n "$end_index" ]]; then
    for ip in "${ip_list[@]}"; do
        index=$((index + 1))
        if (( index >= start_index && index <= end_index )); then
            bash <(curl -s -k 'https://raw.githubusercontent.com/daley7292/sh/refs/heads/main/xrayr.sh') -listenip "$ip" -name "$name-$index" -panel_type "$panel_type" -api_host "$api_host" -api_key "$api_key" -node_id "$node_id" -node_type "$node_type" -proxy_protocol "$proxy_protocol" -dns "$dns" -cert_mode "$cert_mode" -cert_domain "$cert_domain" -cert_file_url "$cert_file_url" -key_file_url "$key_file_url" -dns_provider "$dns_provider" -email "$email" -CLOUDFLARE_EMAIL "$CLOUDFLARE_EMAIL" -CLOUDFLARE_API_KEY_FILE "$CLOUDFLARE_API_KEY_FILE" -inbound_url "$inbound_url" -outbound_url "$outbound_url" -route_url "$route_url"
        fi
    done
else
    for ip in "${ip_list[@]}"; do
        index=$((index + 1))
        bash <(curl -s -k 'https://raw.githubusercontent.com/daley7292/sh/refs/heads/main/xrayr.sh') -listenip "$ip" -name "$name-$index" -panel_type "$panel_type" -api_host "$api_host" -api_key "$api_key" -node_id "$node_id" -node_type "$node_type" -proxy_protocol "$proxy_protocol" -dns "$dns" -cert_mode "$cert_mode" -cert_domain "$cert_domain" -cert_file_url "$cert_file_url" -key_file_url "$key_file_url" -dns_provider "$dns_provider" -email "$email" -CLOUDFLARE_EMAIL "$CLOUDFLARE_EMAIL" -CLOUDFLARE_API_KEY_FILE "$CLOUDFLARE_API_KEY_FILE" -inbound_url "$inbound_url" -outbound_url "$outbound_url" -route_url "$route_url"
    done
fi
