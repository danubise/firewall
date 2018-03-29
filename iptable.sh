#!/usr/bin/env bash

source ./iptables_parameter.sh
echo "FW config start"

#Скорость интернета с учетом QOS
ALLOWMAXSPEED=$(($INTERNETSPEED - $INTERNETSPEED * $QOS / 100))
#максимально разрешенная скорость для нерегистрируемого трафика
echo ${ALLOWMAXSPEED}
LOWLIMIT=$[INTERNETSPEED - 500]

EXTRSPEED=${INTERNETSPEED}

modprobe ifb
ip link set dev ifb0 down
ip link set dev ifb0 up
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "INTERNET Interface TC rules" $EXTR
$TC qdisc del dev $EXTR root
$TC qdisc add dev $EXTR root handle 1: htb default 12
$TC class add dev $EXTR parent 1: classid 1:1 htb rate ${INTERNETSPEED}kbit ceil ${INTERNETSPEED}kbit
#ssh, vpn, suppot.
$TC class add dev $EXTR parent 1:1 classid 1:10 htb rate 10kbit ceil ${ALLOWMAXSPEED}kbit prio 0
#other
$TC class add dev $EXTR parent 1:1 classid 1:11 htb rate 2kbit ceil ${ALLOWMAXSPEED}kbit prio 1
$TC class add dev $EXTR parent 1:1 classid 1:12 htb rate 2kbit ceil ${ALLOWMAXSPEED}kbit prio 6

$TC qdisc add dev $EXTR parent 1:10 handle 100: sfq perturb 10
$TC qdisc add dev $EXTR parent 1:11 handle 110: sfq perturb 10
$TC qdisc add dev $EXTR parent 1:12 handle 120: sfq perturb 10


$TC filter add dev $EXTR parent 1:0 protocol ip prio 1 handle 1 fw classid 1:10
$TC filter add dev $EXTR parent 1:0 protocol ip prio 2 handle 2 fw classid 1:11
$TC filter add dev $EXTR parent 1:0 protocol ip prio 6 handle 3 fw classid 1:12
echo "MARK for " $EXTR
$IPT -t mangle -A OUTPUT -o $EXTR -d $EXTRIP -j MARK --set-mark 1
$IPT -t mangle -A OUTPUT -o $EXTR -d $EXTRIP -j RETURN
$IPT -t mangle -A OUTPUT -o $EXTR -d 0.0.0.0/0 -j MARK --set-mark 3
$IPT -t mangle -A OUTPUT -o $EXTR -d 0.0.0.0/0 -j RETURN

echo "INTERNET Interface TC rules" $EXTR

$IPT -F
$IPT -X
$IPT -t nat -F
$IPT -t nat -X
$IPT -t mangle -F
$IPT -t mangle -X
$IPT -P INPUT ACCEPT
$IPT -P FORWARD ACCEPT
$IPT -P OUTPUT ACCEPT

$TC qdisc del dev $EXTR root
$TC qdisc del dev $EXTR ingress
$TC qdisc del dev $BRIDGE root
$TC qdisc del dev $BRIDGE ingress
$TC qdisc del dev $INT1 root
$TC qdisc del dev $INT1 ingress
$TC qdisc del dev $INT2 root
$TC qdisc del dev $INT2 ingress
echo "delete"
$TC qdisc add dev $INT2 root handle 2: prio
$TC filter add dev $INT2 parent 2: protocol ip  u32 match u32 0 0 action mirred egress redirect dev $BRIDGE
echo "mirroring " $INT2  $BRIDGE

$TC qdisc add dev $INT1 root handle 2: prio
$TC filter add dev $INT1 parent 2: protocol ip  u32 match u32 0 0 action mirred egress redirect dev $BRIDGE
echo "mirroring " $INT1  $BRIDGE

$TC qdisc add dev $BRIDGE root handle 1: htb default 9
$TC class add dev $BRIDGE parent 1: classid 1:1 htb rate ${INT1SPEED}kbit ceil ${INT1SPEED}kbit
$TC class add dev $BRIDGE parent 1:1 classid 1:9 htb rate 80kbit ceil ${INT1SPEED}kbit prio 0
$TC class add dev $BRIDGE parent 1:1 classid 1:10 htb rate ${INTERNETSPEED}kbit ceil ${INTERNETSPEED}kbit prio 0
$TC class add dev $BRIDGE parent 1:10 classid 1:11 htb rate 10kbit ceil ${LOWLIMIT}kbit prio 6

echo "TC start setup filter"
$TC filter add dev $BRIDGE parent 1:0 protocol ip prio 1 handle 9 fw classid 1:9
$TC filter add dev $BRIDGE parent 1:0 protocol ip prio 6 handle 11 fw classid 1:11
echo "tc rules"
$IPT -t nat -A POSTROUTING -o $EXTR -j MASQUERADE

echo "New module from Priority"

echo "Adding rules to Priority table"
if [ ! -f FILE_PRIORITY ]
then
	echo "File exist " $FILE_PRIORITY
	cat $FILE_PRIORITY | grep -v '^#' | while read line
	do
        #$1=ip
        #$2=mark
        #$3=priority
        #$4=bridge name
        #$5=ceil limit
        #$6=filtr prio
        #192.168.0.100 23 6 2400
        PARAMETR=$(echo $line $BRIDGE)
		RULEIPT1=$(echo $PARAMETR| awk '{print "-t mangle -A FORWARD -d "$1" -j MARK --set-mark "$2}')
		RULEIPT2=$(echo $PARAMETR| awk '{print "-t mangle -A FORWARD -d "$1" -j RETURN"}')
		RULETC1=$(echo $PARAMETR| awk '{print " class add dev "$5" parent 1:10 classid 1:"$2" htb rate 10kbit ceil "$4"kbit prio "$3}')
		RULETC2=$(echo $PARAMETR| awk '{print " filter add dev "$5" parent 1:0 protocol ip prio "$3" handle "$2" fw classid 1:"$2}')
		echo $IPT $RULEIPT1
		$IPT $RULEIPT1
		echo $IPT $RULEIPT2
		$IPT $RULEIPT2
		echo $TC $RULETC1
		$TC $RULETC1
		echo $TC $RULETC2
    	$TC $RULETC2
	done

else
 echo "File not found " $FILE_PREROUTING
fi
for var in $LOCALNET
do
    $IPT -t mangle -A FORWARD -d $var -j MARK --set-mark 11
done


$IPT -N sshguard
#уберает блок для  фрагментации пакетов, необходимо для впн
$IPT -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
$IPT -A sshguard -m state --state NEW -m recent --name SSH --rcheck --seconds 1200 --hitcount 3 -j LOG --log-prefix "SSH-shield: "
$IPT -A sshguard -m state --state NEW -m recent --name SSH --update --seconds 1200 --hitcount 3 -j DROP
$IPT -A sshguard -m state --state NEW -m recent --name SSH --set -j ACCEPT
$IPT -A sshguard -j ACCEPT
$IPT -I INPUT -i $EXTR -p tcp --dport 22 -j sshguard

#$IPT -t nat -A PREROUTING -p tcp -i $EXTR --dport 80 -j DNAT --to-destination 192.168.123.210:80
#$IPT -t nat -A PREROUTING -p tcp -i $EXTR --dport 8022 -j DNAT --to-destination 192.168.123.210:22
#$IPT -t nat -A PREROUTING -p tcp -i $EXTR --dport 443 -j DNAT --to-destination 192.168.123.210:443
#$IPT -A FORWARD -p tcp -d 192.168.123.210 -j ACCEPT

if [ ! -f FILE_TASIX ]
then
    $IPT -t nat -N PortForward
    $IPT -t nat -A PortForward -p tcp -i $EXTR --dport 80 -j DNAT --to-destination 192.168.123.210:80
    $IPT -t nat -A PortForward -p tcp -i $EXTR --dport 8022 -j DNAT --to-destination 192.168.123.210:22
    $IPT -t nat -A PortForward -p tcp -i $EXTR --dport 443 -j DNAT --to-destination 192.168.123.210:443
    $IPT -A FORWARD -p tcp -d 192.168.123.210 -j ACCEPT
    $IPT -t nat -N tasix
    cat $FILE_TASIX | grep -v '^#' | while read line
    do
        $IPT -t nat -I tasix -i $EXTR -s $line -j PortForward
    done
    $IPT -t nat -A tasix -i $EXTR -s 0.0.0.0/32 -j RETURN
    $IPT -t nat -A PREROUTING -i $EXTR -j tasix
    #$IPT -I INPUT -i $EXTR -p tcp --dport 80 -j tasix
else
    echo "File not found " $FILE_TASIX
fi
function start(){
    echo "Starting firewall rules"
}
function check(){
    echo "Check function"
}


case $1 in
start)
    echo "Starting firewall rules"
    ;;
restart)
    echo "Restart"
    ;;
*)
  Message="I seem to be running with an nonexistent amount of disk space..."
  ;;
esac
