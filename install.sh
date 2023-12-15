#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# kiểm tra root
[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi：${plain} Script này phải được chạy với quyền người dùng root！\n" && exit 1

# kiểm tra hệ điều hành
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
    echo -e "${red}Script không hỗ trợ hệ thống Alpine！${plain}\n" && exit 1
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
    echo -e "${red}Không xác định được phiên bản hệ thống, vui lòng liên hệ với tác giả script！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Không xác định được kiến trúc, sử dụng kiến trúc mặc định: ${arch}${plain}"
fi

echo "Kiến trúc: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "Phần mềm này không hỗ trợ hệ thống 32 bit (x86), vui lòng sử dụng hệ thống 64 bit (x86_64), nếu phát hiện không chính xác, vui lòng liên hệ với tác giả"
    exit 2
fi

# phiên bản hệ điều hành
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Vui lòng sử dụng CentOS 7 hoặc phiên bản cao hơn！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}Chú ý： CentOS 7 không hỗ trợ giao thức hysteria1/2！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Vui lòng sử dụng Ubuntu 16 hoặc phiên bản cao hơn！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Vui lòng sử dụng Debian 8 hoặc phiên bản cao hơn！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
        yum install ca-certificates wget -y
        update-ca-trust force-enable
    else
        apt-get update -y
        apt install wget curl unzip tar cron socat -y
        apt-get install ca-certificates wget -y
        update-ca-certificates
    fi
}

# 0: đang chạy, 1: không chạy, 2: không cài đặt
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

install_sc() {
    if [[ -e /usr/local/sc/ ]]; then
        rm -rf /usr/local/sc/
    fi

    mkdir /usr/local/sc/ -p
    cd /usr/local/sc/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/qtai2901/sc/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Không thể kiểm tra phiên bản sc, có thể do vượt quá giới hạn API của Github, vui lòng thử lại sau hoặc cài đặt phiên bản sc thủ công${plain}"
            exit 1
        fi
        echo -e "Phát hiện phiên bản mới nhất của sc：${last_version}，bắt đầu cài đặt"
        wget -q -N --no-check-certificate -O /usr/local/sc/sc-linux.zip https://github.com/qtai2901/sc/releases/download/${last_version}/sc-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Tải xuống sc thất bại, vui lòng kiểm tra khả năng tải file từ Github của máy chủ của bạn${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/qtai2901/sc/releases/download/${last_version}/sc-linux-${arch}.zip"
        echo -e "Bắt đầu cài đặt sc $1"
        wget -q -N --no-check-certificate -O /usr/local/sc/sc-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Tải xuống sc $1 thất bại, vui lòng kiểm tra xem phiên bản này có tồn tại không${plain}"
            exit 1
        fi
    fi

    unzip sc-linux.zip
    rm sc-linux.zip -f
    chmod +x sc
    mkdir /etc/sc/ -p
    rm /etc/systemd/system/sc.service -f
    file="https://github.com/qtai2901/sc-script/raw/master/sc.service"
    wget -q -N --no-check-certificate -O /etc/systemd/system/sc.service ${file}
    systemctl daemon-reload
    systemctl stop sc
    systemctl enable sc
    echo -e "${green}Cài đặt sc ${last_version}${plain} hoàn tất, đã thiết lập khởi động cùng hệ thống"
    cp geoip.dat /etc/sc/
    cp geosite.dat /etc/sc/

    if [[ ! -f /etc/sc/config.json ]]; then
        cp config.json /etc/sc/
        echo -e ""
        echo -e "Đây là lần cài đặt đầu tiên, vui lòng tham khảo hướng dẫn: https://github.com/qtai2901/sc/tree/master/example để cấu hình thông tin cần thiết"
        first_install=true
    else
        systemctl start sc
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}sc khởi động lại thành công${plain}"
        else
            echo -e "${red}sc có thể đã khởi động thất bại, vui lòng kiểm tra thông tin nhật ký sc sau đó, nếu không thể khởi động có thể do thay đổi cấu trúc cấu hình, vui lòng xem wiki tại: https://github.com/sc-project/sc/wiki${plain}"
        fi
        first_install=false
    fi

    if [[ ! -f /etc/sc/dns.json ]]; then
        cp dns.json /etc/sc/
    fi
    if [[ ! -f /etc/sc/route.json ]]; then
        cp route.json /etc/sc/
    fi
    if [[ ! -f /etc/sc/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/sc/
    fi
    if [[ ! -f /etc/sc/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/sc/
    fi
    curl -o /usr/bin/sc -Ls https://raw.githubusercontent.com/qtai2901/sc-script/master/sc.sh
    chmod +x /usr/bin/sc
    if [ ! -L /usr/bin/sc ]; then
        ln -s /usr/bin/sc /usr/bin/sc
        chmod +x /usr/bin/sc
    fi
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "Hướng dẫn sử dụng script quản lý sc (tương thích với việc thực thi sc, không phân biệt chữ hoa chữ thường):"
    echo "------------------------------------------"
    echo "sc              - Hiển thị menu quản lý (nhiều chức năng hơn)"
    echo "sc start        - Khởi động sc"
    echo "sc stop         - Dừng sc"
    echo "sc restart      - Khởi động lại sc"
    echo "sc status       - Xem trạng thái sc"
    echo "sc enable       - Bật sc"
    echo "sc disable      - Tắt sc"
    echo "sc log          - Xem nhật ký sc"
    echo "sc x25519       - Tạo khóa riêng sc cho reality"
    echo "sc generate     - Tạo file cấu hình sc"
    echo "
