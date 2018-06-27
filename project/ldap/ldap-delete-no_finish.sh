#/bin/bash

DC="dc=uplooking,dc=com"
ldapUID=ldapuser2
ldapUSER=`ldapsearch -x  -b $DC uid=$ldapUIDUID -LLL | head -1|awk -F ": " '{print $2}'`
rootdn="cn=Manager,dc=uplooking,dc=com"
rootpw=redhat

ldapdelete -x -D $rootdn -w redhat $ldapUSER