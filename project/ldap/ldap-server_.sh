#!/bin/bash

#��װ������
yum -y install openldap-clients openldap-servers openldap migrationtools lftp httpd rpcbind nfs-utils wget

#���hosts����
echo '10.1.1.5 servera' >> /etc/hosts
echo '10.1.1.6 serverb' >> /etc/hosts
echo '10.1.1.7 serverc' >> /etc/hosts

#������ʽ�������ļ���������ʽת��
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

#�����ù����У����ڰ�ȫ��Ҫ��������ؼ��ܣ�����������֤���ļ�
wget -P /tmp ftp://10.1.1.254/project/UP200/UP200_ldap-master/openldap/other/mkcert.sh
chmod 744 /tmp/mkcert.sh
/usr/bin/bash /tmp/mkcert.sh --create-ca-keys
/usr/bin/bash /tmp/mkcert.sh --create-ldap-keys

/usr/bin/cp /etc/pki/CA/my-ca.crt /etc/pki/tls/certs/ca.crt
/usr/bin/cp /etc/pki/CA/ldap_server.crt /etc/pki/tls/certs/slapd.crt
/usr/bin/cp /etc/pki/CA/ldap_server.key /etc/pki/tls/certs/slapd.key

#��openldap�����ļ���һЩ�������ö���Ϳ��������ˡ������ļ�ΪDB_CONFIG��
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

#�����Ŀ
/usr/bin/ldapadd -x -D "cn=admin,cn=config" -w config -f /root/ldif/bdb.ldif -h localhost

#����û���Ŀ�����У�������Ŀ��ʽ����Ƚ��鷳��������ͨ��ldapת���ű���ʵ�ֽ�ϵͳ�û�ת����ldap�û�
#ldif�ļ��ĸ�ʽҪ��ǳ����ǳ����ϸ�һ��Ҫע��հ��в�������
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

#����û���Ŀ��ӵ�ldap���ݿ���
/usr/bin/ldapadd -x -D "cn=Manager,dc=uplooking,dc=com" -w redhat -h localhost -f /root/ldif/base.ldif 
/usr/bin/ldapadd -x -D "cn=Manager,dc=uplooking,dc=com" -w redhat -h localhost -f /root/ldif/password.ldif
/usr/bin/ldapadd -x -D "cn=Manager,dc=uplooking,dc=com" -w redhat -h localhost -f /root/ldif/group.ldif

#����CA֤�鵽web��Ŀ¼��
/usr/bin/cp /etc/pki/tls/certs/ca.crt /var/www/html/
systemctl restart  httpd;systemctl enable  httpd

#����Ŀ¼��ldapuserĿ¼����nfs����
echo '/ldapuser 10.1.1.0/24(rw,sync)' >> /etc/exports
systemctl restart rpcbind;systemctl restart nfs


