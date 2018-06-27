#!/bin/bash

LDAPSERVER=serverc
IPSERVER="10.1.1.5"
DC1=uplooking
DC2=com


setenforce 0
systemctl stop firewalld.service
systemctl disable firewalld.service

#安装所需软件和依赖
yum install -y openldap openldap-clients nss-pam-ldapd  autofs  nfs-utils

#添加hosts解析
echo '10.1.1.5 servera' >> /etc/hosts
echo '10.1.1.6 serverb' >> /etc/hosts
echo '10.1.1.7 serverc' >> /etc/hosts

#下载CA根证书
/usr/sbin/authconfig --enableldap --enableldapauth --ldapserver=$LDAPSERVER --ldapbasedn="dc=$DC1,dc=$DC2" --enableldaptls --ldaploadcacert=http://$LDAPSERVER/ca.crt   --update

#添加自动挂载
echo '/ldapuser /etc/auto.ldap' >> /etc/auto.master
echo "*       -rw,sync        $IPSERVER:/ldapuser/&" >> /etc/auto.ldap
systemctl enable autofs;systemctl start autofs


