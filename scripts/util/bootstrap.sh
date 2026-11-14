#!/bin/bash
timedatectl set-timezone America/Sao_Paulo || ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
apt update -y
apt install -y python3
