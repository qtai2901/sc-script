#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Kiểm tra quyền root
[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi: ${plain} Script này phải được chạy bởi người dùng root!\n" && exit 1

# Kiểm tra hệ điều hành
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
    echo -e "${red}Script không hỗ trợ hệ thống Alpine!${plain}\n" && exit 1
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}Không xác định được phiên bản hệ điều hành, vui lòng liên hệ với tác giả script!${plain}\n" && exit 1
fi

# Phiên bản hệ điều hành
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi



if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Vui lòng sử dụng CentOS 7 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}Chú ý: CentOS 7 không hỗ trợ giao thức hysteria1/2!${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Vui lòng sử dụng Ubuntu 16 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Vui lòng sử dụng Debian 8 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
fi

# Kiểm tra hỗ trợ IPv6 của hệ thống
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # Hỗ trợ IPv6
    else
        echo "0"  # Không hỗ trợ IPv6
    fi
}



confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "khởi động lại " "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Nhấn Enter để quay lại menu chính: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontents.com/qtai2901/sc-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "Nhập phiên bản được chỉ định (mặc định là phiên bản mới nhất): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontents.com/sc/sc-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}Quá trình cập nhật hoàn tất và sc đã được tự động khởi động lại. Vui lòng sử dụng sc log để xem nhật ký đang chạy.${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "sc sẽ tự động khởi động lại sau khi sửa đổi cấu hình."
    nano /etc/sc/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "sc status: ${green}Đã chạy rồi${plain}"
            ;;
        1)
            echo -e "Phát hiện thấy bạn chưa khởi động sc hoặc sc không tự động khởi động lại. Bạn có muốn kiểm tra nhật ký không?[Y/n]" && echo
            read -e -rp "(mặc định: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "sc: ${red}Chưa cài đặt${plain}"
    esac
}

uninstall() {
    confirm "Gỡ cài đặt y/n (mặc định n)?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop sc
    systemctl disable sc
    rm /etc/systemd/system/sc.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/sc/ -rf
    rm /usr/local/sc/ -rf

    echo ""
    echo -e "Để gỡ sạch vui lòng gõ ${green}rm /usr/bin/sc -f${plain} để gỡ"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}sc đã chạy rồi và không cần khởi động lại. Nếu bạn cần khởi động lại, vui lòng chọn khởi động lại.${plain}"
    else
        systemctl start sc
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}sc Đã bắt đầu thành công, vui lòng sử dụng sc log Xem nhật ký chạy${plain}"
        else
            echo -e "${red}sc có thể không khởi động được, vui lòng sử dụng nó sau sc log Xem nhật ký chạy${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    systemctl stop sc
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}sc dừng thành công${plain}"
    else
        echo -e "${red}Quá trình dừng sc không thành công, có thể do thời gian dừng vượt quá hai giây. Vui lòng kiểm tra thông tin nhật ký sau.${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart sc
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}sc Khởi động lại thành công, vui lòng sử dụng sc log Xem nhật ký chạy${plain}"
    else
        echo -e "${red}sc có thể không khởi động được, vui lòng sử dụng sau sc log Xem nhật ký chạy${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status sc --no-pager -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable sc
    if [[ $? == 0 ]]; then
        echo -e "${green}sc Thiết lập tự động khởi động khi bật nguồn thành công${plain}"
    else
        echo -e "${red}sc Không thiết lập được tính năng tự động khởi động khi bật nguồn${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable sc
    if [[ $? == 0 ]]; then
        echo -e "${green}sc Hủy khởi động và tự động khởi động thành công${plain}"
    else
        echo -e "${red}sc Hủy khởi động tự động khởi động thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u sc.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/sc -N --no-check-certificate https://raw.githubusercontent.com/qtai2901/sc-script/master/sc.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}Tập lệnh tải xuống không thành công, vui lòng kiểm tra xem máy có kết nối được không Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/sc
        echo -e "${green}Kịch bản nâng cấp thành công, vui lòng chạy lại kịch bản.${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/sc.service ]]; then
        return 2
    fi
    temp=$(systemctl status sc | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled sc)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1;
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}sc đã được cài đặt, vui lòng không cài đặt lại${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}Vui lòng cài đặt sc trước${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "trạng thái sc: ${green}Đã chạy rồi${plain}"
            show_enable_status
            ;;
        1)
            echo -e "trạng thái sc: ${yellow}Không chạy${plain}"
            show_enable_status
            ;;
        2)
            echo -e "trạng thái sc: ${red}Chưa cài đặt${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Có khởi động tự động sau khi bật nguồn hay không: ${green}Đúng${plain}"
    else
        echo -e "Có khởi động tự động sau khi bật nguồn hay không: ${red}KHÔNG${plain}"
    fi
}

generate_x25519_key() {
    echo -n "đang tạo key x25519："
    /usr/local/sc/sc x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_sc_version() {
    echo -n "version sc："
    /usr/local/sc/sc version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node_config() {
    echo -e "${green}Chọn core：${plain}"
    echo -e "${green}1. xray${plain}"
    echo -e "${green}2. singbox${plain}"
    read -rp "Core?：" core_type
    if [ "$core_type" == "1" ]; then
        core="xray"
        core_xray=true
    elif [ "$core_type" == "2" ]; then
        core="sing"
        core_sing=true
    else
        echo "Lựa chọn không hợp lệ. Vui lòng chọn 1 hoặc 2."
        continue
    fi
    while true; do
        read -rp "Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "Lỗi: Vui lòng nhập đúng số làm Node ID。"
        fi
    done
    
    echo -e "${yellow}Chọn kiểu node：${plain}"
    echo -e "${green}1. Shadowsocks${plain}"
    echo -e "${green}2. Vless${plain}"
    echo -e "${green}3. Vmess${plain}"
    echo -e "${green}4. Hysteria${plain}"
    echo -e "${green}5. Hysteria2${plain}"
    echo -e "${green}6. Tuic${plain}"
    echo -e "${green}7. Trojan${plain}"
    read -rp "Chọn：" NodeType
    case "$NodeType" in
        1 ) NodeType="shadowsocks" ;;
        2 ) NodeType="vless" ;;
        3 ) NodeType="vmess" ;;
        4 ) NodeType="hysteria" ;;
        5 ) NodeType="hysteria2" ;;
        6 ) NodeType="tuic" ;;
        7 ) NodeType="trojan" ;;
        * ) NodeType="shadowsocks" ;;
    esac
    if [ $NodeType == "vless" ]; then
        read -rp "Cài với reality？(y/n)" isreality
    fi
    certmode="none"
    certdomain="example.com"
    if [ "$isreality" != "y" ] && [ "$isreality" != "Y" ]; then
        read -rp "Cài với TLS？(y/n)" istls
        if [ "$istls" == "y" ] || [ "$istls" == "Y" ]; then
           certmode="file"
           certdomain="example.com"
        fi
    fi
    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi
    node_config=""
    if [ "$core_type" == "1" ]; then 
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "https://$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 100,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/sc/quoctai.crt",
                "KeyFile": "/etc/sc/quoctai.key",
                "Email": "quoctai@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        },
EOF
)
    elif [ "$core_type" == "2" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "https://$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 100,
            "TCPFastOpen": true,
            "SniffEnabled": true,
            "EnableDNS": true,
           "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/sc/quoctai.crt",
                "KeyFile": "/etc/sc/quoctai.key",
                "Email": "quoctai@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        },
EOF
)
    fi
    nodes_config+=("$node_config")
}

generate_config_file() {
    
    
    nodes_config=()
    first_node=true
    core_xray=false
    core_sing=false
    
    check_api=false
    
    while true; do
        if [ "$first_node" = true ]; then
            read -rp "Nhập Domain(ko cần https://)：" ApiHost
            read -rp "Nhập API Key：" ApiKey
            
            first_node=false
            add_node_config
        else
            read -rp "Tiếp tục thêm 1 node？(Nhấn Enter để tiếp tục, nhập n hoặc không để thoát)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            else
                read -rp "Nhập Domain(ko cần https://)：" ApiHost
                read -rp "Nhập API Key：" ApiKey
            fi
            add_node_config
        fi
    done

    # 根据核心类型生成 Cores
    if [ "$core_xray" = true ] && [ "$core_sing" = true ]; then
        cores_config="[
        {
            \"Type\": \"xray\",
            \"Log\": {
                \"Level\": \"error\",
                \"ErrorPath\": \"/etc/sc/error.log\"
            },
            \"OutboundConfigPath\": \"/etc/sc/custom_outbound.json\",
            \"RouteConfigPath\": \"/etc/sc/route.json\"
        },
        {
            \"Type\": \"sing\",
            \"Log\": {
                \"Level\": \"error\",
                \"Timestamp\": true
            },
            \"NTP\": {
                \"Enable\": false,
                \"Server\": \"time.apple.com\",
                \"ServerPort\": 0
            },
            \"OriginalPath\": \"/etc/sc/sing_origin.json\"
        }]"
    elif [ "$core_xray" = true ]; then
        cores_config="[
        {
            \"Type\": \"xray\",
            \"Log\": {
                \"Level\": \"error\",
                \"ErrorPath\": \"/etc/sc/error.log\"
            },
            \"OutboundConfigPath\": \"/etc/sc/custom_outbound.json\",
            \"RouteConfigPath\": \"/etc/sc/route.json\"
        }]"
    elif [ "$core_sing" = true ]; then
        cores_config="[
        {
            \"Type\": \"sing\",
            \"Log\": {
                \"Level\": \"error\",
                \"Timestamp\": true
            },
            \"NTP\": {
                \"Enable\": false,
                \"Server\": \"time.apple.com\",
                \"ServerPort\": 0
            },
            \"OriginalPath\": \"/etc/sc/sing_origin.json\"
        }]"
    fi

    # 切换到配置文件目录
    cd /etc/sc
    
    # 备份旧的配置文件
    mv config.json config.json.bak
    nodes_config_str="${nodes_config[*]}"
    formatted_nodes_config="${nodes_config_str%,}"

    # 创建 config.json 文件
    cat <<EOF > /etc/sc/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$formatted_nodes_config]
}
EOF
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/sc/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/sc/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private",
                    "geoip:cn"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "geosite:cn"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                    "regexp:(.+.|^)(360|so).(cn|com)",
                    "regexp:(Subject|HELO|SMTP)",
                    "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                    "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
                    "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                    "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                    "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                    "regexp:(.+.|^)(360).(cn|com|net)",
                    "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
                    "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                    "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                    "regexp:(..||)(visa|mycard|gash|beanfun|bank).",
                    "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
                    "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                    "regexp:(.*.||)(mycard).(com|tw)",
                    "regexp:(.*.||)(gash).(com|tw)",
                    "regexp:(.bank.)",
                    "regexp:(.*.||)(pincong).(rocks)",
                    "regexp:(.*.||)(taobao).(com)",
                    "regexp:(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
                    "regexp:(flows|miaoko).(pages).(dev)"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            }
        ]
    }
EOF

    # 创建 sing_origin.json 文件           
    cat <<EOF > /etc/sc/sing_origin.json
{
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_strategy": "prefer_ipv4"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "outbound": "block",
        "geoip": [
          "private"
        ]
      },
      {
        "geosite": [
          "cn"
        ],
        "outbound": "block"
      },
      {
        "geoip": [
          "cn"
        ],
        "outbound": "block"
      },
      {
        "domain_regex": [
            "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
            "(.+.|^)(360|so).(cn|com)",
            "(Subject|HELO|SMTP)",
            "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
            "(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
            "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
            "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
            "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
            "(.+.|^)(360).(cn|com|net)",
            "(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
            "(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
            "(.*.||)(netvigator|torproject).(com|cn|net|org)",
            "(..||)(visa|mycard|gash|beanfun|bank).",
            "(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
            "(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
            "(.*.||)(mycard).(com|tw)",
            "(.*.||)(gash).(com|tw)",
            "(.bank.)",
            "(.*.||)(pincong).(rocks)",
            "(.*.||)(taobao).(com)",
            "(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
            "(flows|miaoko).(pages).(dev)"
        ],
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": [
          "udp","tcp"
        ]
      }
    ]
  }
}
EOF

    echo -e "${green}Quá trình tạo tệp cấu hình sc đã hoàn tất và dịch vụ sc đang được khởi động lại ${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}Mở cổng tường lửa thành công!${plain}"
}

show_usage() {
    echo " Cách sử dụng tập lệnh quản lý sc: "
    echo "------------------------------------------"
    echo "sc              - Hiển thị menu quản lý (nhiều chức năng hơn)"
    echo "sc start        - khởi động sc"
    echo "sc stop         - dừng sc"
    echo "sc restart      - khởi động lại sc"
    echo "sc status       - trạng thái sc"
    echo "sc enable       - kích hoạt sc"
    echo "sc disable      - Hủy sc tự động khởi động khi khởi động"
    echo "sc log          - Xem nhật ký sc"
    echo "sc x25519       - Tạo khóa x25519"
    echo "sc generate     - Tạo tập tin cấu hình sc"
    echo "sc update       - Cập nhật sc"
    echo "sc update x.x.x - Cài đặt phiên bản sc được chỉ định"
    echo "sc install      - cài đặt sc"
    echo "sc uninstall    - Gỡ cài đặt sc"
    echo "sc version      - Xem phiên bản sc"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  Tập lệnh quản lý phụ trợ ${green}sc, ${plain}${red} không áp dụng được cho docker${plain}
--- https://github.com/qtai2901/sc ---
  ${green}0.${plain} Sửa đổi cấu hình
—————————————————
  ${green}1.${plain} Cài đặt sc
  ${green}2.${plain} Cập nhật sc
  ${green}3.${plain} Gỡ cài đặt sc
—————————————————
  ${green}4.${plain} Bắt đầu sc
  ${green}5.${plain} Dừng sc
  ${green}6.${plain} Khởi động lại sc
  ${green}7.${plain} Xem trạng thái sc
  ${green}8.${plain} Xem nhật ký sc
—————————————————
  ${green}9.${plain} Đặt sc để tự động khởi động khi khởi động
  ${green}10.${plain} Hủy tự động khởi động sc khi khởi động
—————————————————
  ${green}11.${plain} Cài đặt bbr bằng một cú nhấp chuột (kernel mới nhất)
  ${green}12.${plain} Xem phiên bản sc
  ${green}13.${plain} Tạo khóa X25519
  ${green}14.${plain} Nâng cấp tập lệnh bảo trì sc
  ${green}15.${plain} Tạo tệp cấu hình sc
  ${green}16.${plain} Giải phóng tất cả các cổng mạng của VPS
  tập lệnh thoát ${green}17.${plain}
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -rp "请输入选择 [0-17]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_sc_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        17) exit ;;
        *) echo -e "${red}Vui lòng nhập đúng số [0-16]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_sc_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
