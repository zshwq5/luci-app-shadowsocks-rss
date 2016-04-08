#!/bin/sh /etc/rc.common

START=99

EXTRA_COMMANDS="status update_list"
EXTRA_HELP=<<EOF
	Available Commands: 
		status
		udate_list
		help
EOF

PRG_REDIR="/usr/bin/ssr-redir"
PRG_TUNNEL="/usr/bin/ssr-tunnel"
PRG_SERVER="/usr/bin/ssr-server"
PRG_DNSMASQ="/usr/sbin/dnsmasq"
PRG_LOCAL="/usr/bin/ssr-local"
PID_REDIR="/var/run/ssr-redir"
PID_TUNNEL="/var/run/ssr-tunnel"
PID_SERVER="/var/run/ssr-server"
PID_LOCAL="/var/run/ssr-local"

TMP_DIR="/tmp/etc/shadowsocks-rss"
TMP_REDIR="/tmp/etc/shadowsocks-rss/ssr-redir.json"
TMP_SERVER="/tmp/etc/shadowsocks-rss/ssr-server.json"
TMP_LOCAL="/tmp/etc/shadowsocks-rss/ssr-local.json"

DNSMASQ_CACHE=900
DNSMASQ_DIR="/tmp/etc/dnsmasq.d"
DNSMASQ_SERVER="$DNSMASQ_DIR/01-server.conf"
DNSMASQ_IPSET="$DNSMASQ_DIR/02-ipset.conf"

CONFIG_DIR="/etc/shadowsocks-rss"
LIST_DIR="/etc/shadowsocks-rss/list"
GFWLIST="$LIST_DIR/GFWList"
GFWLIST_USER="$LIST_DIR/UserList"
CHINALIST="$LIST_DIR/ChinaList"
BYPASSLIST="$LIST_DIR/BypassList"
GFWLIST_URL="https://raw.githubusercontent.com/wongsyrone/domain-block-list/master/domains.txt"
CHINALIST_URL="http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"


ipset_F() {
	local proxy_mod
	local local_port
	local tunnel_port
	local other_dns
	local other_dns_overall

	config_get proxy_mod $1 proxy_mod
	config_get local_port $1 local_port
	config_get tunnel_port $1 tunnel_port
	config_get other_dns $1 other_dns
	config_get other_dns_overall $1 other_dns_overall

	DNS_OVERALL=0
	[ $other_dns_overall ] && DNS_OVERALL=$other_dns_overall
	TUNNEL_ADDR="127.0.0.1#$tunnel_port"
	
	rm -f $DNSMASQ_IPSET
	rm -f $DNSMASQ_SERVER
	mkdir -p $DNSMASQ_DIR
	
	sed -i '/conf-dir=/d' /etc/dnsmasq.conf
	echo "conf-dir=$DNSMASQ_DIR" >> /etc/dnsmasq.conf

	
	case $proxy_mod in
	G)
#	GFW List
#	echo "	$SERVER_ADDR:$local_port"
	awk '!/^$/&&!/^#/{printf("add BypassList %s''\n",$0)}' $BYPASSLIST > $TMP_DIR/BypassList.ipset
	awk '!/^$/&&!/^#/{printf("ipset=/.%s/'"gfwlist"'\n",$0)}' $GFWLIST > $DNSMASQ_IPSET
	awk '!/^$/&&!/^#/{printf("ipset=/.%s/'"gfwlist"'\n",$0)}' $GFWLIST_USER >> $DNSMASQ_IPSET
	ipset create gfwlist hash:ip -!
	ipset flush gfwlist -!
	ipset create BypassList hash:net -!
	ipset flush BypassList -!
	ipset restore -f $TMP_DIR/BypassList.ipset


	# Create new chain
	iptables -t nat -N SHADOWSOCKS
	iptables -t mangle -N SHADOWSOCKS

	iptables -t nat -A SHADOWSOCKS -d $SERVER_ADDR -j RETURN

	iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set BypassList dst -j RETURN
	iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-ports $local_port

	# Add any UDP rules
	# ip rule add fwmark 0x01/0x01 table 100
	# ip route add local 0.0.0.0/0 dev lo table 100
	# iptables -t mangle -A SHADOWSOCKS -p udp --dport 53 -j TPROXY --on-port $local_port --tproxy-mark 0x01/0x01

	# Apply the rules
	iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS
	iptables -t mangle -A PREROUTING -j SHADOWSOCKS

	# iptables -t nat -I PREROUTING -p tcp -d $SERVER_ADDR -j RETURN
	# iptables -t nat -A PREROUTING -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-port $local_port
	# iptables -t nat -A OUTPUT -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-port $local_port
	;;
	C)
#	ALL the IP address not China
	awk '!/^$/&&!/^#/{printf("add BypassList %s''\n",$0)}' $BYPASSLIST > $TMP_DIR/BypassList.ipset
	awk '!/^$/&&!/^#/{printf("add ChinaList %s''\n",$0)}' $CHINALIST > $TMP_DIR/ChinaList.ipset
	ipset create BypassList hash:net -!
	ipset flush BypassList -!
	ipset restore -f $TMP_DIR/BypassList.ipset
	ipset create ChinaList hash:net -!
	ipset flush ChinaList -!
	ipset restore -f $TMP_DIR/RETURN.ipset

	iptables -t nat -N SHADOWSOCKS
	iptables -t mangle -N SHADOWSOCKS

	iptables -t nat -A SHADOWSOCKS -d $SERVER_ADDR -j RETURN
	iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set BypassList dst -j RETURN
	iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set ChinaList dst -j RETURN
	iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports $local_port

	iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS
	iptables -t mangle -A PREROUTING -j SHADOWSOCKS


	# iptables -t nat -I PREROUTING -p tcp -d $SERVER_ADDR -j RETURN
	# iptables -t nat -I PREROUTING -p tcp -m set --match-set BypassList dst -j RETURN
	# iptables -t nat -I PREROUTING -p tcp -m set --match-set ChinaList dst -j RETURN
	# iptables -t nat -I PREROUTING -p tcp -j REDIRECT --to-port $local_port
	;;
	A)
#	All Public IP address
	awk '!/^$/&&!/^#/{printf("add BypassList %s''\n",$0)}' $BYPASSLIST > $TMP_DIR/BypassList.ipset
	ipset create BypassList hash:net
	ipset flush BypassList -!
	ipset restore -f $TMP_DIR/BypassList.ipset

	iptables -t nat -N SHADOWSOCKS
	iptables -t mangle -N SHADOWSOCKS

	iptables -t nat -A SHADOWSOCKS -d $SERVER_ADDR -j RETURN
	iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set BypassList dst -j RETURN
	iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports $local_port

	iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS
	iptables -t mangle -A PREROUTING -j SHADOWSOCKS
	
	# iptables -t nat -I PREROUTING -p tcp -d $SERVER_ADDR -j RETURN
	# iptables -t nat -I PREROUTING -p tcp -m set --match-set BypassList dst -j RETURN
	# iptables -t nat -I PREROUTING -p tcp -j REDIRECT --to-port $local_port
	;;
	esac

	case $DNS_SERVER in
	T)
#	Shadowsocks Tunnel
	[ $proxy_mod == G ] && {
		sed -i -e "/cache-size=/d" \
			-e "/no-resolv/d" \
			-e "/server=/d" /etc/dnsmasq.conf
		echo "cache-size=$DNSMASQ_CACHE" >> /etc/dnsmasq.conf

		awk -vs="$TUNNEL_ADDR" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			$GFWLIST > $DNSMASQ_SERVER
		}
	[ $proxy_mod == C ] && {
		sed -i -e "/cache-size=/d" \
			-e "/no-resolv/d" \
			-e "/server=/d" /etc/dnsmasq.conf
		echo "cache-size=$DNSMASQ_CACHE" >> /etc/dnsmasq.conf
		echo "no-resolv" >> /etc/dnsmasq.conf
		echo "server=$TUNNEL_ADDR" >> /etc/dnsmasq.conf

		[ "awk '/^nameserver/{print $2}' /etc/resolv.conf" == "127.0.0.1" ] && DNS_RESOLV="awk '/^nameserver/{print $2}' /etc/resolv.conf" || DNS_RESOLV="114.114.114.114"
		awk -vs="$DNS_RESOLV" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			$CHINALIST > $DNSMASQ_SERVER
			}
	[ $proxy_mod == A ] && {
			sed -i -e "/cache-size=/d" \
			-e "/no-resolv/d" \
			-e "/server=/d" /etc/dnsmasq.conf
		echo "cache-size=$DNSMASQ_CACHE" >> /etc/dnsmasq.conf
		echo "no-resolv" >> /etc/dnsmasq.conf
		echo "server=$TUNNEL_ADDR" >> /etc/dnsmasq.conf
		}
	;;
	O)
#	Other DNS Server
	if [ $DNS_OVERALL == 1 -o $proxy_mod == A ]
	then
		sed -i -e "/cache-size=/d" \
			-e "/no-resolv/d" \
			-e "/server=/d" /etc/dnsmasq.conf
		echo "cache-size=$DNSMASQ_CACHE" >> /etc/dnsmasq.conf
		echo "no-resolv" >> /etc/dnsmasq.conf
		echo "server=$other_dns" >> /etc/dnsmasq.conf
	else
		[ $proxy_mod == G ] && {
			sed -i -e "/cache-size=/d" \
			-e "/no-resolv/d" \
			-e "/server=/d" /etc/dnsmasq.conf
			echo "cache-size=$DNSMASQ_CACHE" >> /etc/dnsmasq.conf

			awk -vs="$other_dns" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
				$GFWLIST > $DNSMASQ_SERVER
			}
		[ $proxy_mod == C ] && {
		sed -i -e "/cache-size=/d" \
			-e "/no-resolv/d" \
			-e "/server=/d" /etc/dnsmasq.conf
		echo "cache-size=$DNSMASQ_CACHE" >> /etc/dnsmasq.conf
		echo "no-resolv" >> /etc/dnsmasq.conf
		echo "server=$other_dns" >> /etc/dnsmasq.conf

		[ "awk '/^nameserver/{print $2}' /etc/resolv.conf" == "127.0.0.1" ] && DNS_RESOLV="awk '/^nameserver/{print $2}' /etc/resolv.conf" || DNS_RESOLV="114.114.114.114"
		awk -vs="$DNS_RESOLV" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			$CHINALIST > $DNSMASQ_SERVER
		}
	fi
	;;
	esac
	echo '	ipset_Finished. '

}

ssr_redir() {
	local fast_open
	local one_AUT
	local server
	local server_port
	local local_port
	local password
	local method
	local protocol
	local protocol_param
	local obfs
	local obfs_param
	local timeout

	config_get fast_open $1 fast_open
	config_get one_AUT $1 one_AUT
	config_get server $1 server
	config_get server_port $1 server_port
	config_get local_port $1 local_port
	config_get password $1 password
	config_get method $1 method
	config_get protocol $1 protocol
	config_get protocol_param $1 protocol_param
	config_get obfs $1 obfs
	config_get obfs_param $1 obfs_param
	config_get timeout $1 timeout

	if [ $fast_open == 1 ] 
	then
		FAST_OPEN="true"
		sed -i "/net.ipv4.tcp_fastopen/d" /etc/sysctl.conf
		echo "net.ipv4.tcp_fastopen=3" >> /etc/sysctl.conf
	else
	FAST_OPEN="false"
	fi

	cat > $TMP_REDIR <<EOF
{
    "server": "$server",
    "server_port": $server_port,
    "local_port": $local_port,
    "password": "$password",
    "method": "$method",
    "timeout": $timeout,
    "protocol": "$protocol",
    "protocol_param": "$protocol_param",
    "obfs": "$obfs",
    "obfs_param": "$obfs_param",
    "fast_open": $FAST_OPEN	
}
EOF
		
	[ $one_AUT -a $one_AUT == 1 ] && REDIR_ONE_AUT="-A" || REDIR_ONE_AUT=""

	sleep 1
	service_start $PRG_REDIR -c $TMP_REDIR -b 0.0.0.0 $REDIR_ONE_AUT -f $PID_REDIR 2>/dev/null || return 1
	SERVER_ADDR=$server
	REDIR_LOCAL=$local_port

	echo '	SSR-Redir Loaded. '
}

ssr_tunnel() {
	local tunnel_port
	local dns_server_addr

	config_get tunnel_port $1 tunnel_port
	config_get dns_server_addr $1 dns_server_addr

	sleep 1
	service_start $PRG_TUNNEL -c $TMP_REDIR -b 0.0.0.0 -l $tunnel_port -L $dns_server_addr -u -f $PRG_TUNNEL 2>/dev/null || return 1

	echo '	SSR-Redir Loaded. '
}

ssr_server() {
	local ss_srv_fastopen
	local ss_srv_listen
	local ss_srv_port
	local ss_srv_pwd
	local ss_srv_method
	local ss_srv_prot
	local ss_srv_prot_param
	local ss_srv_obfs
	local ss_srv_obfs_param
	local ss_srv_timeout

	config_get ss_srv_fastopen $1 ss_srv_fastopen
	config_get ss_srv_listen $1 ss_srv_listen
	config_get ss_srv_port $1 ss_srv_port
	config_get ss_srv_pwd $1 ss_srv_pwd
	config_get ss_srv_method $1 ss_srv_method
	config_get ss_srv_prot $1 ss_srv_prot
	config_get ss_srv_prot_param $1 ss_srv_prot_param
	config_get ss_srv_obfs $1 ss_srv_obfs
	config_get ss_srv_obfs_param $1 ss_srv_obfs_param
	config_get ss_srv_timeout $1 ss_srv_timeout

	[ $ss_srv_fastopen -a $ss_srv_fastopen == 1 ] && SRV_FAST_OPEN="true" || SRV_FAST_OPEN="false"
	
	cat > $TMP_SERVER <<EOF
{
    "server": "$ss_srv_listen",
    "server_port": $ss_srv_port,
    "password": "$ss_srv_pwd",
    "method": "$ss_srv_method",
    "timeout": $ss_srv_timeout,
    "protocol": "$ss_srv_prot",
    "protocol_param": "$ss_srv_prot_param",
    "obfs": "$ss_srv_obfs",
    "obfs_param": "$ss_srv_obfs_param",
    "fast_open": $SRV_FAST_OPEN	
}
EOF

	sleep 1
	service_start $PRG_SERVER -c $TMP_SERVER $ONE_AUT -f $PID_SERVER 2>/dev/null || return 1

	echo '	SSR-Server Loaded. '

}

ssr_local() {
	local local_port
	local ss_local_port

	config_get local_port $1 local_port 
	config_get ss_local_port $1 ss_local_port 

	cp $TMP_REDIR $TMP_LOCAL
	
	sed -i "s/\"local_port\": $local_port\,/\"local_port\": $ss_local_port\,/g" $TMP_LOCAL
	
	sleep 1
	service_start $PRG_LOCAL -c $TMP_LOCAL -b 0.0.0.0 -u $ONE_AUT -f $PID_LOCAL 2>/dev/null || return 1
	echo '	SSR-Local Loaded. '

}

ssr_header() {
	local enabled
	local ss_server
	local ss_local
	local dns_server

	config_get enabled $1 enabled
	config_get ss_server $1 ss_server
	config_get ss_local $1 ss_local
	config_get dns_server $1 dns_server

	ENABLE=$enabled
	SS_SERVER=$ss_server
	SS_LOCAL=$ss_local
	DNS_SERVER=$dns_server
}

start() {
	echo ''
	config_load shadowsocks-rss
	config_foreach ssr_header

	if [ $ENABLE -a $ENABLE == 1 ]
	then

		mkdir -p $TMP_DIR
		echo -e '\033[40;33;1m Starting RSS-Redir server... \033[0m'
		config_foreach ssr_redir
		config_foreach ipset_F

		echo -e '\033[40;33;1m Starting DNS server... \033[0m'
		[ $DNS_SERVER == T ] && config_foreach ssr_tunnel || echo '	SSR-Tunnel	Disabled. Using Other DNS Server. '
		/etc/init.d/dnsmasq restart

		echo -e '\033[40;33;1m Starting Other server...\033[0m'
		[ $SS_SERVER == 1 ] && config_foreach ssr_server || echo '	SSR-Server Disabled. '
		[ $SS_LOCAL == 1 ] && config_foreach ssr_local || echo '	SSR-Server Disabled. '

		echo -e 'Shadowsocks-RSS Start		\033[40;32;1m Finished \033[0m '
		echo ''
		echo -e '\033[40;33;1m Checking... \033[0m '
		status
	else if [ $SS_SERVER == 1 -o $SS_LOCAL == 1 ]
		then
			echo -e '\033[40;33;1m Shadowsocks-RSS SSR-Redir Disabled. Starting Other server... \033[0m'
			[ $SS_SERVER == 1 ] && config_foreach ssr_server || echo '	SSR-Server Disabled. '
			[ $SS_LOCAL == 1 ] && config_foreach ssr_local || echo '	SSR-Server Disabled. '
			
			echo -e "Shadowsocks-RSS Start \033[40;32;1mFinished\033[0m. "
			echo ''
			echo -e '\033[40;33;1m Checking... \033[0m '
			status
		else echo "Shadowsocks-RSS Disabled. "
		fi
	fi

	echo ' '
}

stop() {
	echo ''
	echo -e '\033[40;33;1m Stopping Shadowsocks-RSS Server... \033[0m '
	while [ $(ps|grep ${PRG_REDIR}|grep -v grep|wc -l) -ge 1 ]
	do
	service_stop $PRG_REDIR
	done
	echo -e '	SSR-Redir		\033[40;31;1m Stoped \033[0m '
	
	while [ $(ps|grep ${PRG_TUNNEL}|grep -v grep|wc -l) -ge 1 ]
	do
		service_stop $PRG_TUNNEL
	done
	echo -e '	SSR-Tunnel		\033[40;31;1m Stoped \033[0m '

	sed -i -e "/cache-size=/d " \
		-e "/no-resolv/d" \
		-e "/server=/d" /etc/dnsmasq.conf 
		
	rm -f $DNSMASQ_IPSET
	rm -f $DNSMASQ_SERVER
	rm -f -R $TMP_DIR
	
	while [ $(ps|grep ${PRG_SERVER}|grep -v grep|wc -l) -ge 1 ]
	do
	service_stop $PRG_SERVER
	done
	echo -e '	SSR-Server		\033[40;31;1m Stoped \033[0m '
	
	while [ $(ps|grep ${PRG_LOCAL}|grep -v grep|wc -l) -ge 1 ]
	do
	service_stop $PRG_LOCAL
	done
	echo -e '	SSR-Local		\033[40;31;1m Stoped \033[0m '

	echo -e '	Ipset			\033[40;31;1m Disabled \033[0m '
	{
	iptables -F
	iptables -X
	iptables -t nat -F
	iptables -t nat -X
	iptables -t mangle -F
	iptables -t mangle -X
	iptables -t raw -F
	iptables -t raw -X
	iptables -P INPUT ACCEPT
	iptables -P FORWARD ACCEPT
	iptables -P OUTPUT ACCEPT
	
	ipset flush gfwlist -!
	ipset flush ChinaList -!
#	ipset flush BypassList -!
#	ipset destroy GFWList -!
	}  2>/dev/null

	/etc/init.d/firewall restart 2>/dev/null
	/etc/init.d/dnsmasq restart

	echo -e ' Shadowsocks-RSS Server		\033[40;31;1m Stoped \033[0m '
	echo ''
}

restart() {
	stop
	sleep 3
	echo ''
	start

}

status() {
	local enabled=`uci get shadowsocks-rss.@basic[0].enabled 2>/dev/null`
	local fast_open=`uci get shadowsocks-rss.@basic[0].fast_open 2>/dev/null`
	local proxy_mod=`uci get shadowsocks-rss.@basic[0].proxy_mod 2>/dev/null`
	local local_port=`uci get shadowsocks-rss.@basic[0].local_port 2>/dev/null`
	local tunnel_port=`uci get shadowsocks-rss.@basic[0].tunnel_port 2>/dev/null`
	local ss_srv_port=`uci get shadowsocks-rss.@basic[0].ss_srv_port 2>/dev/null`
	local ss_local_port=`uci get shadowsocks-rss.@basic[0].ss_local_port 2>/dev/null`
	local ss_server=`uci get shadowsocks-rss.@basic[0].ss_server 2>/dev/null`
	local ss_local=`uci get shadowsocks-rss.@basic[0].ss_local 2>/dev/null`
	local dns_server=`uci get shadowsocks-rss.@basic[0].dns_server 2>/dev/null`
	local other_dns=`uci get shadowsocks-rss.@basic[0].other_dns 2>/dev/null`

	echo -e '\033[40;33;1m Shadowsocks-RSS Server Status: \033[0m'
	echo ''
	[ $enabled == 1 ] && echo -e '	Autostarts: 		\033[40;32;1m Enable \033[0m' || echo -e '	Autostarts: 		\033[40;31;1m Disable \033[0m'
	[ $fast_open -a $fast_open == 1 ] && echo -e '	TCP Fast Open: 		\033[40;32;1m Enable \033[0m' || echo -e '	TCP Fast Open: 		\033[40;31;1m Disable \033[0m'
	case $proxy_mod in
	G)
	echo -e '	Proxy Mod: 		\033[40;32;1m GFWList \033[0m'
	;;
	C)
	echo -e '	Proxy Mod: 		\033[40;32;1m Other Than China \033[0m'
	;;
	A)
	echo -e '	Proxy Mod: 		\033[40;32;1m All Public IP address \033[0m'
	;;
	esac
	if [ $ss_server == 1 -a $ss_local == 1 ]
	then
		echo -e '	Other Service: 		\033[40;33;1m ss-server + ss-local \033[0m'
	else if [ $ss_server == 1 -a $ss_local == 0 ]
		then
			echo -e '	Other Service: 		\033[40;33;1m ss-server \033[0m'
		else if [ $ss_server == 0 -a $ss_local == 1 ]
			then 
				echo -e '	Other Service: 		\033[40;33;1m ss-local \033[0m'
			else echo -e '	Other Service: 		\033[40;31;1m Disabled \033[0m'
			fi
		fi
	fi
	echo ''
	[ $(ps|grep ${PRG_REDIR}|grep -v grep|wc -l) -ge 1 ] && echo -e "	SSR-Redir		\033[40;32;1m Running \033[0m 		Port: \033[40;34;1m $local_port \033[0m		PID: \033[40;34;1m $(pidof ${PRG_REDIR##*/}) \033[0m" || echo -e '	SSR-Redir		\033[40;31;1m Stopped \033[0m '
	case $dns_server in
	T)
	[ $(ps|grep ${PRG_TUNNEL}|grep -v grep|wc -l) -ge 1 ] && echo -e "	SSR-Tunnel		\033[40;32;1m Running \033[0m 		Port: \033[40;34;1m $tunnel_port \033[0m		PID: \033[40;34;1m $(pidof ${PRG_TUNNEL##*/}) \033[0m" || echo -e '	SSR-Tunnel		\033[40;31;1m Stopped \033[0m '
	;;
	O)
	echo -e "	DNS-Server		\033[40;32;1m $other_dns \033[0m"
	;;
	N)
	echo -e '	DNS-Server		\033[40;32;1m System Default \033[0m Besure your system DNS is clean.'
	;;
	esac
	[ $(ps|grep ${PRG_SERVER}|grep -v grep|wc -l) -ge 1 ] && echo -e "	SSR-Server		\033[40;32;1m Running \033[0m 		Port: \033[40;34;1m $ss_srv_port \033[0m		PID: \033[40;34;1m $(pidof ${PRG_SERVER##*/}) \033[0m" || echo -e '	SSR-Server		\033[40;31;1m Stopped \033[0m ' 
	[ $(ps|grep ${PRG_LOCAL}|grep -v grep|wc -l) -ge 1 ] && echo -e "	SSR-Local		\033[40;32;1m Running \033[0m 		Port: \033[40;34;1m $ss_local_port \033[0m		PID: \033[40;34;1m $(pidof ${PRG_LOCAL##*/}) \033[0m" || echo -e '	SSR-Local		\033[40;31;1m Stopped \033[0m ' 
	[ $(ps|grep ${PRG_DNSMASQ}|grep -v grep|wc -l) -ge 1 ] && echo -e "	DNSMasq			\033[40;32;1m Running \033[0m 		Port: \033[40;34;1m 53 \033[0m		PID: \033[40;34;1m $(pidof ${PRG_DNSMASQ##*/}) \033[0m" || echo -e '	DNSMasq		\033[40;31;1m Stopped \033[0m ' 
	echo ''
}

update_list() {
	mkdir -p $TMP_DIR

	echo 'GFWList Updating...'
	cp $GFWLIST $LIST_DIR/GFWList.backup

	wget --no-check-certificate -b -q -P $TMP_DIR $GFWLIST_URL
	[ -e $TMP_DIR/domains.txt ] && cp $TMP_DIR/domains.txt $GFWLIST && echo '	GFWList Updated. '|| echo '	Download GFWList Fail. '
	rm -f $TMP_DIR/domains.txt
	echo ''

	echo 'ChinaList Updating...'
	cp $CHINALIST $LIST_DIR/ChinaList.backup
	curl --progress-bar $CHINALIST_URL \
		| grep ipv4 | grep CN | awk -F\| '{ printf("%s/%d\n", $4, 32-log($5)/log(2)) }' > $TMP_DIR/ChinaList.txt 
	[ -e $TMP_DIR/ChinaList.txt ] && cp $TMP_DIR/ChinaList.txt $CHINALIST && echo '	ChinaList Updated. ' || echo '	Download ChinaList Fail. '
	rm -f $TMP_DIR/ChinaList.txt
}

help() {

	echo -e 'Available Commands:'
	echo -e '	\033[40;33;1m status \033[0m	Checking Program status.'
	echo -e "	\033[40;33;1m udate_list \033[0m	Update ChinaList And GFWList. Buckup Is in The Floder $LIST_DIR"
	echo -e '	\033[40;33;1m help	 \033[0m	This help. '

}