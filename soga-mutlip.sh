#!/bin/bash
ALLOWED_OPTIONS="start_index end_index name webapi_url webapi_key server_type node_id soga_key routes_url cert_domain cert_mode dns_provider DNS_CF_Email DNS_CF_Key cert_url dns"
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
ip_list=($(ip -4 addr show | awk '/inet / {print $2}' | cut -d'/' -f1 | grep -vE '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])|169\.254|^0\.|^255\.)'))
if [[ -n "$start_index" && -n "$end_index" ]]; then
    for ip in "${ip_list[@]}"; do
        index=$((index + 1))
        if (( index >= start_index && index <= end_index )); then
            bash <(curl -s -k 'https://raw.githubusercontent.com/daley7292/sh/refs/heads/main/soga.sh') -name \"$name-$index\" webapi_url $webapi_url -webapi_key $webapi_key -server_type $server_type -soga_key $soga_key -node_id $node_id -routes_url $routes_url -listen $ip -dns $dns
        fi
    done
else
    for ip in "${ip_list[@]}"; do
        index=$((index + 1))
            bash <(curl -s -k 'https://raw.githubusercontent.com/daley7292/sh/refs/heads/main/soga.sh') -name "$name-$index" -webapi_url $webapi_url -webapi_key $webapi_key -server_type $server_type -soga_key $soga_key -node_id $node_id -routes_url $routes_url -listen $ip -dns $dns
    done
fi
