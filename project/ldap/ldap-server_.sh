#!/bin/bash

#安装依赖包
yum -y install openldap-clients openldap-servers openldap migrationtools lftp httpd rpcbind nfs-utils wget

#添加hosts解析
echo '10.1.1.5 servera' >> /etc/hosts
echo '10.1.1.6 serverb' >> /etc/hosts
echo '10.1.1.7 serverc' >> /etc/hosts

#产生旧式的配置文件，并做格式转换
cat > /etc/openldap/slapd.conf << EOF
include         /etc/openldap/schema/corba.schema
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/duaconf.schema
include         /etc/openldap/schema/dyngroup.schema
include         /etc/openldap/schema/inetorgperson.schema
include         /etc/openldap/schema/java.schema
include         /etc/openldap/schema/misc.schema
include         /etc/openldap/schema/nis.schema
include         /etc/openldap/schema/openldap.schema
include         /etc/openldap/schema/pmi.schema
include         /etc/openldap/schema/ppolicy.schema
include         /etc/openldap/schema/collective.schema
allow bind_v2
pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args
####  Encrypting Connections
TLSCACertificateFile /etc/pki/tls/certs/ca.crt
TLSCertificateFile /etc/pki/tls/certs/slapd.crt
TLSCertificateKeyFile /etc/pki/tls/certs/slapd.key
### Enable Monitoring
database monitor
# allow only rootdn to read the monitor
access to * by dn.exact="cn=admin,cn=config" read by * none
### Database Config###          
database config
access to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
rootdn "cn=admin,cn=config"
EOF

/usr/sbin/slappasswd -s config |sed -e "s#{SSHA}#rootpw\t{SSHA}#g" >>/etc/openldap/slapd.conf
rm -fr /etc/openldap/slapd.d/*
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d/
chown -R ldap.ldap  /etc/openldap/slapd.d/
chmod -R u+rwX /etc/openldap/slapd.d
chmod 000 /etc/openldap/slapd.conf

#在配置过程中，由于安全需要，启动相关加密，生成相关相关证书文件
wget -P /tmp ftp://10.1.1.254/project/UP200/UP200_ldap-master/openldap/other/mkcert.sh
chmod 744 /tmp/mkcert.sh
/usr/bin/bash /tmp/mkcert.sh --create-ca-keys
/usr/bin/bash /tmp/mkcert.sh --create-ldap-keys

/usr/bin/cp /etc/pki/CA/my-ca.crt /etc/pki/tls/certs/ca.crt
/usr/bin/cp /etc/pki/CA/ldap_server.crt /etc/pki/tls/certs/slapd.crt
/usr/bin/cp /etc/pki/CA/ldap_server.key /etc/pki/tls/certs/slapd.key

#对openldap数据文件做一些基本配置定义就可以启动了。配置文件为DB_CONFIG。
rm -fr /var/lib/ldap/*
/usr/bin/cp -p /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap.  /var/lib/ldap/
systemctl start  slapd.service ; systemctl enable  slapd.service

mkdir /root/ldif
cat > /root/ldif/bdb.ldif <<EOF
dn: olcDatabase=bdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcBdbConfig
olcDatabase: {1}bdb
olcSuffix: dc=uplooking,dc=com
olcDbDirectory: /var/lib/ldap
olcRootDN: cn=Manager,dc=uplooking,dc=com
olcRootPW: redhat
olcLimits: dn.exact="cn=Manager,dc=uplooking,dc=com" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn,displayName pres,eq,approx,sub
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: memberUid eq
olcDbIndex: objectClass eq
olcDbIndex: entryUUID pres,eq
olcDbIndex: entryCSN pres,eq
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.children="ou=admins,dc=uplooking,dc=com" write  by * none
olcAccess: to * by self write by dn.children="ou=admins,dc=uplooking,dc=com" write by * read
EOF

#添加条目
/usr/bin/ldapadd -x -D "cn=admin,cn=config" -w config -f /root/ldif/bdb.ldif -h localhost

#添加用户条目过程中，本身条目格式定义比较麻烦，所以我通过ldap转换脚本来实现将系统用户转换成ldap用户
#ldif文件的格式要求非常，非常的严格，一定要注意空白行不能少了
sed -i '71,74s/padl/uplooking/' /usr/share/migrationtools/migrate_common.ph

mkdir -p /ldapuser
groupadd ldapuser1 -g 100001
useradd ldapuser1 -u 100001 -g 100001 -d /ldapuser/ldapuser1
groupadd ldapuser2 -g 100002
useradd ldapuser2 -u 100002 -g 100002 -d /ldapuser/ldapuser2
echo 123123 | passwd --stdin ldapuser1
echo 123456 | passwd --stdin ldapuser2
grep ldapuser /etc/passwd > /root/ldap_user.txt
grep ldapuser /etc/group > /root/ldap_group.txt

/usr/share/migrationtools/migrate_base.pl > /root/ldif/base.ldif
/usr/share/migrationtools/migrate_passwd.pl /root/ldap_user.txt  > /root/ldif/password.ldif
/usr/share/migrationtools/migrate_group.pl /root/ldap_group.txt > /root/ldif/group.ldif

#最后将用户条目添加到ldap数据库中
/usr/bin/ldapadd -x -D "cn=Manager,dc=uplooking,dc=com" -w redhat -h localhost -f /root/ldif/base.ldif 
/usr/bin/ldapadd -x -D "cn=Manager,dc=uplooking,dc=com" -w redhat -h localhost -f /root/ldif/password.ldif
/usr/bin/ldapadd -x -D "cn=Manager,dc=uplooking,dc=com" -w redhat -h localhost -f /root/ldif/group.ldif

#复制CA证书到web根目录下
/usr/bin/cp /etc/pki/tls/certs/ca.crt /var/www/html/
systemctl restart  httpd;systemctl enable  httpd

#将根目录下ldapuser目录进行nfs共享
echo '/ldapuser 10.1.1.0/24(rw,sync)' >> /etc/exports
systemctl restart rpcbind;systemctl restart nfs


