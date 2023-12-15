#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
    echo -e "${red}脚本暂不支持alpine系统！${plain}\n" && exit 1
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
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
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
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
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

install_sc() {
    if [[ -e /usr/local/sc/ ]]; then
        rm -rf /usr/local/sc/
    fi

    mkdir /usr/local/sc/ -p
    cd /usr/local/sc/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/qtai2901/sc/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 sc 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 sc 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 sc 最新版本：${last_version}，开始安装"
        wget -q -N --no-check-certificate -O /usr/local/sc/sc-linux.zip https://github.com/qtai2901/sc/releases/download/${last_version}/sc-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 sc 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/qtai2901/sc/releases/download/${last_version}/sc-linux-${arch}.zip"
        echo -e "开始安装 sc $1"
        wget -q -N --no-check-certificate -O /usr/local/sc/sc-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 sc $1 失败，请确保此版本存在${plain}"
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
    #cp -f sc.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop sc
    systemctl enable sc
    echo -e "${green}sc ${last_version}${plain} 安装完成，已设置开机自启"
    cp geoip.dat /etc/sc/
    cp geosite.dat /etc/sc/

    if [[ ! -f /etc/sc/config.json ]]; then
        cp config.json /etc/sc/
        echo -e ""
        echo -e "全新安装，请先参看教程：https://github.com/qtai2901/sc/tree/master/example，配置必要的内容"
        first_install=true
    else
        systemctl start sc
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}sc 重启成功${plain}"
        else
            echo -e "${red}sc 可能启动失败，请稍后使用 sc log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/sc-project/sc/wiki${plain}"
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
    curl -o /usr/bin/sc -Ls https://raw.githubusercontent.com/qtai2910/sc-script/master/sc.sh
    chmod +x /usr/bin/sc
    if [ ! -L /usr/bin/sc ]; then
        ln -s /usr/bin/sc /usr/bin/sc
        chmod +x /usr/bin/sc
    fi
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "sc 管理脚本使用方法 (兼容使用sc执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "sc              - 显示管理菜单 (功能更多)"
    echo "sc start        - 启动 sc"
    echo "sc stop         - 停止 sc"
    echo "sc restart      - 重启 sc"
    echo "sc status       - 查看 sc 状态"
    echo "sc enable       - 设置 sc 开机自启"
    echo "sc disable      - 取消 sc 开机自启"
    echo "sc log          - 查看 sc 日志"
    echo "sc x25519       - 生成 x25519 密钥"
    echo "sc generate     - 生成 sc 配置文件"
    echo "sc update       - 更新 sc"
    echo "sc update x.x.x - 更新 sc 指定版本"
    echo "sc install      - 安装 sc"
    echo "sc uninstall    - 卸载 sc"
    echo "sc version      - 查看 sc 版本"
    echo "------------------------------------------"
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装sc,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            curl -o ./initconfig.sh -Ls https://raw.githubusercontent.com/qtai2901/sc-script/master/initconfig.sh
            source initconfig.sh
            rm initconfig.sh -f
            generate_config_file
            read -rp "是否安装bbr内核 ?(y/n): " if_install_bbr
            if [[ $if_install_bbr == [Yy] ]]; then
                install_bbr
            fi
        fi
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_sc $1
