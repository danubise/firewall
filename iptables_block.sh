#!/usr/bin/env bash

IFS_TEMP=$IFS
IFS=$'\n'
set -x
/sbin/iptables -I INPUT -i ens2f1 -s 192.168.123.0/24 -d 192.168.123.254/24 -j REJECT
for dhcprule in $(grep host /etc/dhcp/dhcpd.conf )
do
# iptables -I INPUT -i ens2f1 -m mac --mac-source 1c:1b:0d:fa:bc:52 -s 192.168.123.181 -j ACCEPT
	MACIP=$(echo $dhcprule | awk '{print $6}')
	IPADDR=$(echo $dhcprule | awk '{print $9}')
#	echo $MACIP"\n"
	/sbin/iptables -I INPUT -i ens2f1 -m mac --mac-source $MACIP -s $IPADDR -j ACCEPT
done
/sbin/iptables -I INPUT -i ens2f1 -p udp --dport 67:68 --sport 67:68 -j ACCEPT
#/sbin/iptables -I INPUT -i ens2f1 -s 192.168.123.0/24 -d 192.168.123.254/32 -j ACCEPT
IFS=$IFS_TEMP
set +x
