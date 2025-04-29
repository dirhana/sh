#!/bin/sh  # 使用 sh
ALLOWED_OPTIONS="d h ip dns"
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

check_debian() {
  if grep -qi "debian" /etc/os-release; then
    echo "当前系统是 Debian 系统。"
  else
    echo "当前系统不是 Debian 系统。脚本中止。"
    exit 1
  fi
}

# 检查是否是 Arch 系统
check_arch() {
if grep -qi "arch" /etc/os-release; then
  ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
  echo "当前系统是 Arch Linux 系统。"
else
  echo "当前系统不是 Arch Linux 系统。脚本中止。"
  exit 1
fi
}

install_packages_debian() {
apt update && apt upgrade -y && apt autoremove -y && apt install -y bc gpg curl wget dnsutils net-tools bash-completion systemd-timesyncd vim nftables vnstat systemd-journal-remote syslog-ng python3 qemu-guest-agent
}

install_packages_arch() {
pacman-key --init && pacman-key --populate archlinux
pacman -Syu --noconfirm && pacman -S --noconfirm bc curl wget dnsutils net-tools bash-completion vim nftables vnstat syslog-ng python3 qemu-guest-agent
}

configure_timesync() {
timedatectl set-timezone Asia/Shanghai
rm -f /etc/systemd/timesyncd.conf
cat << EOF > /etc/systemd/timesyncd.conf
[Time]
NTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
FallbackNTP=ntp.ubuntu.com time.apple.com
EOF
systemctl unmask systemd-timesyncd
systemctl enable systemd-timesyncd
systemctl restart systemd-timesyncd
}

configure_resolved() {
rm -rf /etc/resolv.conf
find /etc/systemd/network/ -type f -exec sed -i '/^DNS=/d' {} +
if [ -n "$dns" ]; then
  echo "设置DNS为: $dns"
cat  <<EOF >/etc/systemd/resolved.conf
[Resolve]
DNS=$dns
FallbackDNS=1.1.1.1 1.0.0.1
Cache=no
EOF
else
    echo "没有提供DNS参数，设置DNS为 1.1.1.1。"
cat  <<EOF >/etc/systemd/resolved.conf
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com
FallbackDNS=1.0.0.1#cloudflare-dns.com
EOF
fi
systemctl unmask systemd-resolved
systemctl enable systemd-resolved
systemctl restart systemd-resolved
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
}

configure_sysctl() {
rm -rf /etc/sysctl.conf
rm -rf /etc/sysctl.d/*
cat <<EOF >/etc/sysctl.d/99-custom.conf
# 文件系统优化
fs.file-max = 1000000
fs.inotify.max_user_instances = 131072

# 内核网络参数优化
net.core.default_qdisc = fq
net.core.somaxconn = 65535

# IPv4 基础网络参数
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.ip_forward = 1
net.ipv4.route.flush = 1
net.ipv4.ping_group_range = 0 2147483647
net.ipv4.ip_local_port_range = 10000 49999

# TCP 网络优化
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 2
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_max_syn_backlog = 4194304
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_mem = 786432 1048576 3145728
net.ipv4.tcp_rmem = 16384 131072 67108864
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 30
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# IPv6 网络配置
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.all.autoconf = 1

# 虚拟内存管理
vm.swappiness = 40

EOF
ln -s /etc/sysctl.d/99-custom.conf /etc/sysctl.conf

total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_memory_bytes=$((total_memory * 1024))
total_memory_gb=$(awk "BEGIN {printf \"%.2f\", $total_memory / 1024 / 1024}")
if [[ ${total_memory_gb//.*/} -lt 4 ]]; then    
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =262144 786432 2097152#g" /etc/sysctl.conf
elif [[ ${total_memory_gb//.*/} -ge 4 && ${total_memory_gb//.*/} -lt 7 ]]; then
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =524288 1048576 2097152#g" /etc/sysctl.conf
elif [[ ${total_memory_gb//.*/} -ge 7 && ${total_memory_gb//.*/} -lt 11 ]]; then    
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =786432 1048576 3145728#g" /etc/sysctl.conf
elif [[ ${total_memory_gb//.*/} -ge 11 && ${total_memory_gb//.*/} -lt 15 ]]; then    
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =1048576 1572864 3145728#g" /etc/sysctl.conf
elif [[ ${total_memory_gb//.*/} -ge 15 && ${total_memory_gb//.*/} -lt 20 ]]; then    
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =2097152 3145728 4194304#g" /etc/sysctl.conf
elif [[ ${total_memory_gb//.*/} -ge 20 && ${total_memory_gb//.*/} -lt 25 ]]; then    
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =3145728 4194304 8388608#g" /etc/sysctl.conf
elif [[ ${total_memory_gb//.*/} -ge 25 && ${total_memory_gb//.*/} -lt 30 ]]; then
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =6291456 8388608 16777216#g" /etc/sysctl.conf
else
  sed -i "s#.*net.ipv4.tcp_mem =.*#net.ipv4.tcp_mem =6291456 8388608 16777216#g" /etc/sysctl.conf
fi
sysctl -p &> /dev/null
}

configure_limits() {
echo "1000000" > /proc/sys/fs/file-max
sed -i '/ulimit -SHn/d' /etc/profile
echo "ulimit -SHn 1000000" >>/etc/profile
ulimit -SHn 1000000 && ulimit -c unlimited
cat <<EOF >/etc/security/limits.conf
*     soft   nofile    1048576
*     hard   nofile    1048576
*     soft   nproc     1048576
*     hard   nproc     1048576
*     soft   core      1048576
*     hard   core      1048576
*     hard   memlock   unlimited
*     soft   memlock   unlimited
EOF
}

configure_systemd() {
echo "[Manager]" > /etc/systemd/system.conf
echo "DefaultTimeoutStopSec=30s" >> /etc/systemd/system.conf
echo "DefaultLimitCORE=infinity" >> /etc/systemd/system.conf
echo "DefaultLimitNOFILE=20480000" >> /etc/systemd/system.conf
echo "DefaultLimitNPROC=20480000" >> /etc/systemd/system.conf
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
echo -e "[Service]\nTimeoutStartSec=1sec" > /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
systemctl daemon-reload
systemctl daemon-reexec
}

enable_vnstat() {
systemctl enable vnstat.service --now
}

configure_syslog_ng() {
if [ -z "$ip" ]; then
  echo "没有提供目标 IP 地址，跳过 syslog-ng 配置。"
  return 0  # 跳过该函数，不做任何操作
fi
echo "正在配置 /etc/syslog-ng/syslog-ng.conf..."
cat <<EOF > /etc/syslog-ng/syslog-ng.conf
@include "scl.conf"

source s_local {
    system();
    internal();
};

destination d_remote {
    syslog("$ip" port(514) transport("udp"));
};

log { 
    source(s_local); 
    destination(d_remote); 
};

options {
    chain_hostnames(off);
    create_dirs(yes);
    dns_cache(no);
    flush_lines(0);
    group("log");
    keep_hostname(yes);
    log_fifo_size(10000);
    perm(0640);
    stats(freq(0));
    time_reopen(10);
    use_dns(no);
    use_fqdn(no);
};
EOF
systemctl enable --now syslog-ng@default
systemctl restart syslog-ng@default
}

install_docker() {
if [ -z "$d" ]; then
  echo "没有 -d 选项,跳过 docker 安装。"
  return 0  # 跳过该函数，不做任何操作
fi
mkdir -p /etc/docker
printf '{"log-driver": "syslog","log-opts": {"tag":"{{.Name}}"}}\n' > /etc/docker/daemon.json
if command -v docker &>/dev/null; then
  docker_version=$(docker --version | awk '{print $3}')
  echo -e "Docker 已安装，版本：$docker_version"
else
  if [ -f /etc/arch-release ]; then
    echo "检测到 Arch Linux 系统，使用 pacman 安装 Docker。"
    pacman -S --noconfirm docker docker-compose
  else
    echo -e "开始安装 Docker..."
    rm -rf /etc/containerd
    curl -fsSL https://get.docker.com | sh
    rm -rf /opt/containerd
    echo -e "Docker 安装完成。"
  fi
fi
sleep 3
rm -rf /opt/containerd
mkdir -p /etc/containerd && touch /etc/containerd/config.toml
echo -e "[plugins]\n  [plugins.'io.containerd.internal.v1.opt']\n    path = '/var/lib/containerd'" | tee /etc/containerd/config.toml > /dev/null
systemctl enable --now docker
systemctl restart docker
cat <<EOF >>/etc/sysctl.d/99-custom.conf
net.netfilter.nf_conntrack_max = 65535
net.netfilter.nf_conntrack_buckets = 16384
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_established = 300
EOF
total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_memory_bytes=$((total_memory * 1024))
total_memory_gb=$(awk "BEGIN {printf \"%.2f\", $total_memory / 1024 / 1024}")
nf_conntrack_max=$((total_memory_bytes / 16384  ))
nf_conntrack_buckets=$((nf_conntrack_max / 4))
sed -i "s#.*net.netfilter.nf_conntrack_max = .*#net.netfilter.nf_conntrack_max = ${nf_conntrack_max}#g" /etc/sysctl.conf
sed -i "s#.*net.netfilter.nf_conntrack_buckets = .*#net.netfilter.nf_conntrack_buckets = ${nf_conntrack_buckets}#g" /etc/sysctl.conf
}


set_hostname() {
if [ -n "$h" ]; then
  echo "设置主机名为: $h"
  hostnamectl set-hostname "$h"
  sed -i "s/127.0.1.1.*/127.0.1.1 $h/" /etc/hosts
else
    echo "没有提供主机名参数，跳过主机名设置。"
fi
}

create_reboot_timer() {
    # 定时器文件路径
    TIMER_FILE="/etc/systemd/system/reboot.timer"
    SERVICE_FILE="/etc/systemd/system/reboot.service"

    # 检查定时器文件是否已经存在
    if [ -f "$TIMER_FILE" ]; then
        echo "定时器 reboot.timer 已经存在。"
    else
        # 创建 systemd 服务文件
        echo "创建 reboot.service 文件..."
        echo "[Unit]" > "$SERVICE_FILE"
        echo "Description=Reboot the system" >> "$SERVICE_FILE"
        echo "" >> "$SERVICE_FILE"
        echo "[Service]" >> "$SERVICE_FILE"
        echo "Type=oneshot" >> "$SERVICE_FILE"
        echo "ExecStart=/sbin/reboot" >> "$SERVICE_FILE"

        # 创建 systemd 定时器文件
        echo "创建 reboot.timer 文件..."
        echo "[Unit]" > "$TIMER_FILE"
        echo "Description=Timer for daily system reboot at 4 AM" >> "$TIMER_FILE"
        echo "" >> "$TIMER_FILE"
        echo "[Timer]" >> "$TIMER_FILE"
        echo "OnCalendar=*-*-* 04:00:00" >> "$TIMER_FILE"
        echo "Unit=reboot.service" >> "$TIMER_FILE"
        echo "" >> "$TIMER_FILE"
        echo "[Install]" >> "$TIMER_FILE"
        echo "WantedBy=timers.target" >> "$TIMER_FILE"

        # 重新加载 systemd 配置
        echo "重新加载 systemd 配置..."
        systemctl daemon-reload

        # 启动并启用定时器
        echo "启用并启动 reboot.timer 定时器..."
        systemctl enable --now reboot.timer

        echo "reboot.timer 已成功创建并启用，定时任务将在每天凌晨 4 点执行重启。"
    fi
}

main() {
echo "">/etc/motd
if grep -qi "debian" /etc/os-release; then
  check_debian
  install_packages_debian
elif grep -qi "arch" /etc/os-release; then
  check_arch
  install_packages_arch
else
  echo "不支持的操作系统。脚本中止。"
  exit 1
fi
configure_timesync
configure_resolved
configure_sysctl
configure_limits
configure_systemd
enable_vnstat
install_docker
configure_syslog_ng
set_hostname
}
parse_options "$@"
main
reboot
