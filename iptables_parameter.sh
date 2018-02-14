#!/usr/bin/env bash
set +x
IPT=/sbin/iptables
TC=/sbin/tc
#скорость интернет канала
INTERNETSPEED=3000
QOS=20
#сетефой интерфейс для интернета
EXTR=enp2s0
EXTRIP=195.158.26.218
#сетевой интерфейс 100МБит
INT1=enp3s0
INT1SPEED=102400
#сетевой интерфейс 100МБит
INT2=enp4s0
INT1SPEED=102400
BRIDGE=ifb0
LOCALNET="192.168.69.0/24 192.168.0.0/24"
FILE_PRIORITY="/etc/iptables/PRIORITY_RULES"
set -x