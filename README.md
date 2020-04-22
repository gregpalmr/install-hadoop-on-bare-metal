# install-hadoop-on-bare-metal

This repo contains scripts and procedures for installing Apache Hadoop on bare-metal servers running CentOS/Red Hat 7.7.x


## Step 1. Use this repo

     $ git clone https://github.com/gregpalmr/install-hadoop-on-bare-metal

     $ cd install-hadoop-on-bare-metal

## Step 2. Configure the cluster-wide ssh and scp utility scripts

This Hadoop install procedure uses several BASH scripts that assist in running remote shell commands remote copy commands on the hadoop edge nodes, master nodes and worker nodes. These scripts can be found in:

     install-hadoop-on-bare-metal/scripts/cssh   - cluster ssh

     install-hadoop-on-bare-metal/scripts/cscp   - cluster scp

To begin using these utilities, you must configure the scripts to know what hostnames to use as they carry out commands on the Hadoop cluster nodes. Follow these steps to configure the utility.

### a. View the options for the cssh script

     $ ./cssh --help

      Usage: cssh [--help | --setup | -e | -n | -d ] <remote command>
          Where --setup means setup the passwordless ssh environment
          Where -e means only run command on edge nodes
          Where -n means only run command on name nodes
          Where -d means only run command on data nodes

      Examples: cssh "ps -ef"
                cssh -e "ps -ef"
                cssh -n "ps -ef"
                cssh -d "ps -ef"
                cssh --setup

### b. Modify the cssh script to use hostname templates that resolve to your hostnames.

Edit the cssh bash script file.

     $ vi cssh

Change the following shell script lines to use template matching strings that reflect the naming convention of your servers' hostnames. For example, if the hostnames of your master nodes are:

     hadoopcluster1namenode1.mydomain.com
     hadoopcluster1namenode2.mydomain.com
     hadoopcluster1namenode3.mydomain.com

then you would define the EDGE_NODES_HOSTNAME_TEMPLATE shell variable as:

     EDGE_NODES_HOSTNAME_TEMPLATE="hadoopcluster1master[].mydomain.com"

Similarly, if the hostnames of your worker nodes are:

     hadoopcluster1datanode1.mydomain.com

     hadoopcluster1datanode2.mydomain.com

     hadoopcluster1datanode3.mydomain.com

then you would define the NAME_NODES_HOSTNAME_TEMPLATE shell variable as:

     NAME_NODES_HOSTNAME_TEMPLATE="hadoopcluster1datanode[].mydomain.com"

Finally, if the hostnames of your edge node (or access nodes) are:

     hadoopcluster1edgenode1.mydomain.com

     hadoopcluster1edgenode2.mydomain.com

     hadoopcluster1edgenode3.mydomain.com

then you would define the DATA_NODES_HOSTNAME_TEMPLATE shell variable as:

     DATA_NODES_HOSTNAME_TEMPLATE="hadoopcluster1edgenode[].mydomain.com"

Additionally, you must configure the number of edge nodes, master nodes and worker nodes by change the values of these shell variables:

     NUM_EDGE_NODES=1
     NUM_NAME_NODES=3
     NUM_DATA_NODES=10

### c. Configure the public and private SSL keys used to access your Hadoop cluster nodes.

If you already have SSL keys for the user that you will use to install Hadoop on this cluster, then you can simply modify the shell variable to point to the private SSL key:

     SSH_KEY=$HOME/.ssh/my_existing_id_rsa_private_key

If you don't have an existing SSL key for SSH sessions, you can use this cssh script to create one and copy it to all the servers in your cluster. Use the following command to create an SSL key and copy it to all the servers:

     $ cssh --setup

It will prompt you for the password of your current logged in user as it copies the SSL key to each server.


## Step 2.  Prepare the Bare-metal servers for the Hadoop install

In this section, you will be running the cssh script commands from your edge node server.

### a. Set Swappiness to none

     SEE: 
     https://community.hortonworks.com/articles/8563/typical-hdp-cluster-network-configuration-best-pra.html
     https://community.cloudera.com/t5/Community-Articles/OS-Configurations-for-Better-Hadoop-Performance/ta-p/247300

     $ cssh "echo 'vm.swappiness=9' >> /etc/sysctl.conf && sysctl -w vm.swappiness=9"

### b. Disable Transparent Huge Page

     This old way (RHEL 6) doesn't work in RHEL 7
     # cssh "echo never > cat /sys/kernel/mm/transparent_hugepage/enabled"

     RHEL 7 can tune THP with the tuned system service

     $ cssh "mkdir -p /etc/tuned/nothp_profile"

     $ cssh "
cat > /etc/tuned/nothp_profile/tuned.conf <<EOF
[main]
include= throughput-performance

[vm]
transparent_hugepages=never
EOF
"
     $ cssh "chmod +x /etc/tuned/nothp_profile/tuned.conf"

     $ cssh "tuned-adm profile nothp_profile"

     $ cssh "cat /sys/kernel/mm/transparent_hugepage/enabled"

### c. Increase the number of open files

     $ cssh "echo 'fs.file-max=2097152' >> /etc/sysctl.conf 
     $ sysctl -p && cat /proc/sys/fs/file-max"


### d. Setup Chrony Network Time Protocol 
-------------------------------------------

     Check if crony is running

     $ cssh "systemctl status chronyd.service | grep -e Loaded -e Active"

     If needed, install crony

     $ cssh "yum -y install chrony"
     $ cssh "systemctl start chronyd.service && systemctl enable chronyd.service"

     Check if crony is referencing time sources
     $ cssh "chronyc sources"

     Check if crony is tracking
     $ cssh "chronyc tracking"


### e. Setup OpenLDAP (Optional)

     SEE: 
     https://community.cloudera.com/t5/Community-Articles/How-to-setup-OpenLDAP-2-4-on-CentOS-7/ta-p/249263
     https://www.itzgeek.com/how-tos/linux/centos-how-tos/step-step-openldap-server-configuration-centos-7-rhel-7.html

     Run the following command to install OpenLDAP server on the edge node and the OpenLDAP client on the master nodes and worker nodes.

     $ yum -y install openldap compat-openldap openldap-clients openldap-servers openldap-servers-sql openldap-devel

     $ systemctl start slapd.service
     $ systemctl enable slapd.service
     $ netstat -antup | grep -i 389

     Get the hash for the root ldap password

     $ slappasswd -h {SSHA} -s changeme
          {SSHA}RfySeypjO0OJ2sPCo+Mn3FotCGTLfZ4v

     Change the following configuration with your domain information (mycompany.com)

     $ cat > /tmp/ldap-db.ldif << EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=local,dc=net

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=ldapadm,dc=local,dc=net

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: {SSHA}RfySv5KjO0OJ2sPCo+Mn3FotCGTLfZ4v
EOF

     $ ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/ldap-db.ldif

     Restrict monitor access to the ldapadm user. Change the following configuration with your domain information (mycompany.com):

     $ cat > /tmp/monitor.ldif <<EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external, cn=auth" read by dn.base="cn=ldapadm,dc=local,dc=net" read by * none
EOF

     $ ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/monitor.ldif

     Create an SSL cert to connect with

     $ openssl req -new -x509 -nodes -out /etc/openldap/certs/ldap.mydomain.com.cert -keyout /etc/openldap/certs/ldap.mydomain.com.key -days 365
     $ chown ldap:ldap /etc/openldap/certs/ldap.mydomain.com.*

     $ cat > /tmp/certs.ldif <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/ldap.mydomain.com.cert

dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/ldap.mydomain.com.key
EOF

     $ ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certs.ldif

     $ slaptest -u

     Create the LDAP database

     $ cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
     $ chown ldap:ldap /var/lib/ldap/*

     Add the cosine and nis LDAP schemas.

     $ ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
     $ ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif 
     $ ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

     $ cat > /tmp/base.ldif <<EOF
dn: dc=local,dc=net
dc: local
objectClass: top
objectClass: domain

dn: cn=ldapadm,dc=local,dc=net
objectClass: organizationalRole
cn: ldapadm
description: LDAP Manager

dn: ou=People,dc=local,dc=net
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=local,dc=net
objectClass: organizationalUnit
ou: Group
EOF

     $ ldapadd -x -W -D "cn=ldapadm,dc=local,dc=net" -f /tmp/base.ldif

     Add a real user to the ldap directory

     $ cssh "groupadd --gid 1029 hadoopusers"
     $ cssh "useradd --uid 1030 -d /home/myuser myuser"
     $ passwd myuser    # enter password changeme
     $ cssh "usermod --groups hadoopusers myuser"

     gidNumber is the gid in /etc/group for user myuser

     $ cat > /tmp/user_myuser.ldif  <<EOF
dn: uid=myuser,ou=People,dc=local,dc=net
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: myuser
uid: myuser
uidNumber: 1030
gidNumber: 1030
homeDirectory: /home/myuser
loginShell: /bin/bash
gecos: Me [myuser (at) mycompany.com]
userPassword: {crypt}x
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
EOF
	
     $ ldapadd -x -W -D "cn=ldapadm,dc=local,dc=net" -f /tmp/user_myuser.ldif

     From any node, list all LDAP users (gets default LDAP svr from /etc/openldap/ldap.conf)

     $ 	ldapsearch -x -W -D "cn=ldapadm,dc=local,dc=net" -b dc=local,dc=net 

     OR

     $ 	cssh "ldapsearch -x -w changeme -D "cn=ldapadm,dc=local,dc=net" -b dc=local,dc=net | grep uid=" 

### f. Create Hadoop Linux Users

     get the encrypted version of the password

     $ perl -e 'print crypt("changeme", "salt"),"\n"'. # saJwgELO4ozwU

     $ cssh "groupadd --gid 1020 hadoop"

     $ cssh "useradd -d /home/hadoop                  --uid 1020 --gid hadoop hadoop"
     $ cssh "useradd -d /home/hadoop --no-create-home --uid 1021 --gid hadoop hdfs"
     $ cssh "useradd -d /home/hadoop --no-create-home --uid 1023 --gid hadoop yarn"
     $ cssh "useradd -d /home/hadoop --no-create-home --uid 1022 --gid hadoop mapred"
     $ cssh "useradd -d /home/hadoop --no-create-home --uid 1024 --gid hadoop hive"
     $ cssh "useradd -d /home/hadoop --no-create-home --uid 1025 --gid hadoop hbase"
     $ cssh "useradd -d /home/hadoop --no-create-home --uid 1026 --gid hadoop zookeeper"

     Allow members of the group hadoop to read & write to /home/hadoop

     $ cssh "chmod -R g+rw /home/hadoop && chmod -R o-rw /home/hadoop"

     $ cssh "id hadoop && id hdfs && id yarn && id mapred && id hive && id hbase && id zookeeper"


### g. Install Kerberos (Optional)

     SEE:
     https://hadoop.apache.org/docs/r2.4.1/hadoop-project-dist/hadoop-common/SecureMode.html 
     https://www.theurbanpenguin.com/configuring-a-centos-7-kerberos-kdc/

     On the edge node/admin node, install all packages

     $ yum -y install -y krb5-server krb5-workstation pam_krb5

     On all the Hadoop cluster nodes, only install the client packages

     $ cssh "yum -y install -y krb5-workstation pam_krb5 &"

     $ cssh "yum list installed krb5*"

     On the edge node/admin node, setup the Kerberos KDC config files

     $ cat > /var/kerberos/krb5kdc/kdc.conf <<EOF

[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 MYDOMAIN.COM = {
  #master_key_type = aes256-cts
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  supported_enctypes = aes256-cts:normal aes128-cts:normal des3-hmac-sha1:normal arcfour-hmac:normal camellia256-cts:normal camellia128-cts:normal des-hmac-sha1:normal des-cbc-md5:normal des-cbc-crc:normal
EOF

     $ cat > /var/kerberos/krb5kdc/kadm5.acl <<EOF
*/admin@MYDOMAIN.COM      *
EOF

     Setup the Kerberos client config files on all cluster nodes

     Add entry to kerb5.conf file

     $ cssh "
cat > /etc/krb5.conf <<EOF

# Configuration snippets may be placed in this directory as well
includedir /etc/krb5.conf.d/

[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 #pkinit_anchors = /etc/pki/tls/certs/ca-bundle.crt
 default_realm = MYDOMAIN.COM
 default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 MYDOMAIN.COM = {
  kdc = hadoopcluster1edgenode1.mydomain.com
  admin_server = hadoopcluster1edgenode1.mydomain.com
 }

[domain_realm]
.mydomain.com = MYDOMAIN.COM
mydomain.com = MYDOMAIN.COM

EOF
"

     On the edge node/admin node, initialize the Kerberos database

     Make sure the rngd service is running

     $ ps -ef|grep rngd

     Create the Kerberos database

     $ kdb5_util create -s -r MYDOMAIN.COM
        <enter password> # changeme

     Start the kerberbos service

     $ systemctl start krb5kdc kadmin
     $ systemctl enable krb5kdc kadmin

     Create Kerberos Principals

     Create the root principal

     $ kadmin.local
         kadmin.local: addprinc root/admin # enter password changeme
         kadmin.local: quit

     Create the Hadoop Kerberos principals

     Set the operation: delprinc or addprinc

     OP=addprinc
     #OP=delprinc

     # EDGE NODES
     for i in {1..1} # edge nodes
     do
       for svc in hdfs yarn mapred hive hbase HTTP
       do
         if [ "$OP" == "addprinc" ]; then
           echo "addprinc -randkey ${svc}/hadoopcluster1edgenode${i}.mydomain.com@MYDOMAIN.COM"   | kadmin.local
         else
           echo "delprinc -force ${svc}/hadoopcluster1edgenode${i}.mydomain.com@MYDOMAIN.COM"    | kadmin.local
         fi
       done
     done

     # NAME NODES
     for i in {1..3} # name nodes
     do
       for svc in hdfs yarn mapred hive hbase HTTP
       do
         if [ "$OP" == "addprinc" ]; then
           echo "addprinc -randkey ${svc}/hadoopcluster1namenode${i}.mydomain.com@MYDOMAIN.COM"   | kadmin.local
         else
           echo "delprinc -force ${svc}/hadoopcluster1namenode${i}.mydomain.com@MYDOMAIN.COM"    | kadmin.local
         fi

       done
     done

     # DATA NODES
     for i in {1..5} # data nodes
     do
       for svc in hdfs yarn mapred hive hbase HTTP
       do
         if [ "$OP" == "addprinc" ]; then
           echo "addprinc -randkey ${svc}/hadoopcluster1datanode${i}.mydomain.com@MYDOMAIN.COM"   | kadmin.local
         else
           echo "delprinc -force ${svc}/hadoopcluster1datanode${i}.mydomain.com@MYDOMAIN.COM"    | kadmin.local
         fi
       done
     done

     List the new principals

     $ echo listprincs | kadmin.local 


     Create the Kerberos keytab files for the hdfs, mapred and yarn services
     hdfs.keytab is used for NameNode, SecondaryNameNode and DataNodes
     mapred.keytab is used for MapReduce Job History Server
     yarn.keytab is used for ResourceManager and NodeManager

     EDGE NODES

     for i in {1..1} # edge nodes
     do
       for svc in hdfs yarn mapred
       do
         echo "xst -norandkey -k hadoopcluster1edgenode${i}.${svc}.keytab ${svc}/hadoopcluster1edgenode${i}.mydomain.com@MYDOMAIN.COM HTTP/hadoopcluster1edgenode${i}.mydomain.com@MYDOMAIN.COM" | kadmin.local
       done
     done

     # NAME NODES
     for i in {1..3} # name nodes
     do
       for svc in hdfs yarn mapred
       do
         echo "xst -norandkey -k hadoopcluster1namenode${i}.${svc}.keytab ${svc}/hadoopcluster1namenode${i}.mydomain.com@MYDOMAIN.COM HTTP/hadoopcluster1namenode${i}.mydomain.com@MYDOMAIN.COM" | kadmin.local
       done
     done

     # DATA NODES
     for i in {1..5} # data nodes
     do
       for svc in hdfs yarn mapred
       do
         echo "xst -norandkey -k hadoopcluster1datanode${i}.${svc}.keytab ${svc}/hadoopcluster1datanode${i}.mydomain.com@MYDOMAIN.COM HTTP/hadoopcluster1datanode${i}.mydomain.com@MYDOMAIN.COM" | kadmin.local
       done
     done

     # List the new keytab info
     for svc in hdfs yarn mapred
     do
        for kt in *.${svc}.keytab
        do
           klist -e -k -t ${kt}
        done
     done
     echo
     ls -al *.keytab 

     Distribute the .keytab files to each server

     $ chown hdfs:hadoop *.hdfs.keytab
     $ chown yarn:hadoop *.yarn.keytab
     $ chown mapred:hadoop *.mapred.keytab
     $ chmod 400 *.keytab

     $ cssh "mkdir -p /etc/hadoop/conf/keytab"

     $ mv *.hdfs.keytab /etc/hadoop/conf/keytab && mv *.yarn.keytab /etc/hadoop/conf/keytab && mv *.mapred.keytab /etc/hadoop/conf/keytab

     for i in {1..1} # edge nodes
     do
       for svc in hdfs yarn mapred
       do
         scp -i ~/.ssh/id_rsa_cssh /etc/hadoop/conf/hadoopcluster1edgenode${i}.${svc}.keytab hadoopcluster1edgenode${i}.mydomain.com:/etc/hadoop/conf/keytab/${svc}.keytab
       done
     done

     for i in {1..3} # name nodes
     do
       for svc in hdfs yarn mapred
       do
         scp -i ~/.ssh/id_rsa_cssh /etc/hadoop/conf/hadoopcluster1namenode${i}.${svc}.keytab hadoopcluster1namenode${i}.mydomain.com:/etc/hadoop/conf/keytab/${svc}.keytab
       done
     done

     for i in {1..5} # data nodes
     do
       for svc in hdfs yarn mapred
       do
         scp -i ~/.ssh/id_rsa_cssh /etc/hadoop/conf/hadoopcluster1datanode${i}.${svc}.keytab hadoopcluster1datanode${i}.mydomain.com:/etc/hadoop/conf/keytab/${svc}.keytab
       done
     done

     Check to see if the keytab files are setup corrrectly

     $ cssh "ls -al /etc/hadoop/conf/keytab/*.keytab"

     for svc in hdfs yarn mapred
     do
       cssh "klist -e -k -t /etc/hadoop/conf/keytab/${svc}.keytab"
     done


### h. Install Apache Big Top (Optional - needed for JSVC_HOME and datanode security)

     $ cssh "wget -O /etc/yum.repos.d/bigtop.repo www.apache.org/dist/bigtop/bigtop-1.4.0/repos/centos7/bigtop.repo"

     $ cssh "yum clean all"

     $ cssh "yum -y install bigtop-utils &"


### i. Install Java JRE/JDK

     Install OpenJDK 8

     $ cssh "yum -y install java-1.8.0-openjdk &"

     $ cssh "java -version"

     $ cssh "echo '
export JAVA_HOME=/usr/lib/jvm/jre-1.8.0
' > /etc/profile.d/java_env.sh"

     $ cssh "cat /etc/profile.d/java_env.sh"

     $ cssh " echo \$JAVA_HOME"


### j. Install Zookeeper

     $ cssh -n "curl -O http://ftp.wayne.edu/apache/zookeeper/stable/apache-zookeeper-3.5.7-bin.tar.gz &"
     $ cssh -n "tar -xf apache-zookeeper-3.5.7-bin.tar.gz -C /var/lib/"

     $ cssh -n "echo '
tickTime=2000
dataDir=/home/hadoop/data/zookeeper
clientPort=2181 
' >> /var/lib/apache-zookeeper-3.5.7-bin/conf/zoo.cfg"

     $ cssh "mkdir -p /home/hadoop/data && chown hadoop:hadoop /home/hadoop/data && chmod 770 /home/hadoop/data"

     $ cssh -n "mkdir -p /home/hadoop/data/zookeeper && chown zookeeper:hadoop /home/hadoop/data/zookeeper"
     $ cssh -n "chown -R zookeeper:hadoop /var/lib/apache-zookeeper-3.5.7-bin"

     $ cssh -n "echo '
export ZOOKEEPER_INSTALL=/var/lib/apache-zookeeper-3.5.7-bin
export PATH=\$PATH:\$ZOOKEEPER_INSTALL/bin
' > /etc/profile.d/zookeeper_env.sh" 

     Start the zookeeper daemons as the zookeeper user

     $ cssh -n "sudo su zookeeper -c '/var/lib/apache-zookeeper-3.5.7-bin/bin/zkServer.sh start'"

     $ cssh -n "netstat -antp | grep 2181"

## Step 3. Install Apache Hadoop

     SEE: 
     https://hadoop.apache.org/docs/r2.10.0/hadoop-project-dist/hadoop-common/ClusterSetup.html
     https://hadoop.apache.org/docs/r2.10.0/hadoop-project-dist/hadoop-common/SecureMode.html
     BOOK: Practical Hadoop Security By Bhushan Lakhe 

### a. Setup Hadoop environment variables 

     $ cssh "echo '
export HADOOP_PREFIX=/var/lib/hadoop-2.10.0
export HADOOP_CONF_DIR=/etc/hadoop/conf
export HADOOP_HOME=\${HADOOP_PREFIX}
export HADOOP_COMMON_HOME=\${HADOOP_PREFIX}
export HADOOP_HDFS_HOME=\${HADOOP_PREFIX}
export HADOOP_MAPRED_HOME=\${HADOOP_PREFIX}
export YARN_HOME=\${HADOOP_PREFIX}
export HADOOP_LOG_DIR=/var/log/hadoop
export PATH=\$PATH:\$HADOOP_PREFIX/bin:\$HADOOP_PREFIX/sbin
export DEFAULT_LIBEXEC_DIR=\$HADOOP_PREFIX/libexec
export HADOOP_NAMENODE_OPTS="-XX:+UseParallelGC"
' > /etc/profile.d/hadoop_env.sh"

     $ cssh "echo JAVA_HOME=\$JAVA_HOME - HADOOP_HOME=\$HADOOP_HOME - HADOOP_CONF_DIR=\$HADOOP_CONF_DIR"

### b. Setup the SSL Certificates keystore and trustore

     SEE: https://docs.cloudera.com/HDPDocuments/HDP3/HDP-3.0.0/configuring-wire-encryption/sec_configuring_wire_encryption.pdf

     $ cssh "mkdir -p /etc/hadoop/conf/tls/certs"

     Create the keystore and certificate:

     $ cssh "keytool -genkeypair -keystore /etc/hadoop/conf/tls/certs/keystore.jks -alias `hostname -f` -validity 365 -keypass changeme -storepass changeme -dname \"CN=`hostname -f`, OU=Dremio, O=Dremio, L=Albany, ST=NY, C=US\" "

     Create the Certificate Authority (CA)

     $ cssh "openssl req -new -x509 -keyout /etc/hadoop/conf/tls/certs/ca-key -out /etc/hadoop/conf/tls/certs/ca-cert -nodes -days 365 -subj \"/CN=`hostname -f`/OU=Dremio/O=Dremio/L=Albany/ST=NY/C=US\" "

     Add the generated CA to the server's truststore

     $ cssh "keytool -keystore /etc/hadoop/conf/tls/certs/server.truststore.jks -storepass changeme -keypass changeme -alias CARoot -noprompt -import -file /etc/hadoop/conf/tls/certs/ca-cert"

     Add the generated CA to the client's truststore

     $ cssh "keytool -keystore /etc/hadoop/conf/tls/certs/client.truststore.jks -storepass changeme -keypass changeme -alias CARoot -noprompt -import -file /etc/hadoop/conf/tls/certs/ca-cert"

     $ cssh "ls -al /etc/hadoop/conf/tls/certs/"

     Sign all certificates with the CA
     First, export the certificate from the keystore

     $ cssh "keytool -keystore /etc/hadoop/conf/tls/certs/keystore.jks -alias `hostname -f` -storepass changeme -certreq -file /etc/hadoop/conf/tls/certs/exported-cert-file "

     Second, sign the certificate with the CA

     $ cssh "openssl x509 -req -CA /etc/hadoop/conf/tls/certs/ca-cert -CAkey /etc/hadoop/conf/tls/certs/ca-key -in /etc/hadoop/conf/tls/certs/exported-cert-file -out /etc/hadoop/conf/tls/certs/cert-signed -days 365 -CAcreateserial -passin pass:changeme "

     Import the CA certificate and the signed certificate into the keystore

     $ cssh "keytool -keystore /etc/hadoop/conf/tls/certs/server.keystore.jks -alias CARoot -import -storepass changeme -noprompt -file /etc/hadoop/conf/tls/certs/ca-cert "

     $ cssh "keytool -keystore /etc/hadoop/conf/tls/certs/server.keystore.jks -alias localhost -import -storepass changeme -noprompt -file /etc/hadoop/conf/tls/certs/cert-signed"

     $ cssh "chown -R hadoop:hadoop /etc/hadoop/conf && chmod 440 /etc/hadoop/conf/tls/certs/*"

     ssl.server.keystore.location
     ssl.server.keystore.keypassword
     ssl.client.truststore.location
     ssl.client.truststore.password

### c. Download Apache Hadoop binaries

     SEE: https://www.apache.org

     $ cssh "curl -L -# -O https://downloads.apache.org/hadoop/common/hadoop-2.10.0/hadoop-2.10.0.tar.gz"

     $ cssh "tar xf hadoop-2.10.0.tar.gz -C /var/lib/ && chown -R hadoop:hadoop /var/lib/hadoop-2.10.0"
     $ cssh "ls -al /var/lib/hadoop-2.10.0"

     Create the hadoop data dir on the master nodes 

     $ cssh -n "mkdir -p /home/hadoop/data && chown hadoop:hadoop /home/hadoop/data && chmod 770 /home/hadoop/data"

     Change the owner of the data node's data directories

     $ cssh -d "chown -R hdfs:hadoop /data_* && chmod 770 /data_*"

     Create the logs dir for hadoop daemon log files

     $ cssh "mkdir -p /var/log/hadoop && chown -R hadoop:hadoop /var/log/hadoop && chmod 770 /var/log/hadoop"

### d. Configure the Hadoop 2.10.0 daemons in the xml config files. The following setup enables name node HA using the Hadoop Journal Quorum Manager

     SEE: https://hadoop.apache.org/docs/r2.10.0/hadoop-project-dist/hadoop-hdfs/HDFSHighAvailabilityWithQJM.html

     Setup the configuration file: /etc/hadoop/conf/hadoop-env.sh

     $ cssh "cp $HADOOP_HOME/etc/hadoop/hadoop-env.sh $HADOOP_CONF_DIR"

     Setup the configuration file: /etc/hadoop/conf/core-site.xml

     $ cssh "echo '
<configuration>

  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://cluster1</value>
  </property>

  <property>
     <name>ha.zookeeper.quorum</name>
     <value>hadoopcluster1namenode1.mydomain.com:2181,hadoopcluster1namenode2.mydomain.com:2181,hadoopcluster1namenode3.mydomain.com:2181</value>
  </property>

  <property>
     <name>hadoop.security.authentication</name>
     <value>kerberos</value> <!-- A value of "simple" would disable security. -->
  </property>
  <property>
     <name>hadoop.security.authorization</name>
     <value>true</value>
  </property>

  <property>
    <name>hadoop.proxyuser.root.hosts</name>
    <value>*</value>
  </property>
  <property>
    <name>hadoop.proxyuser.root.groups</name>
    <value>*</value>
  </property>
  <property>
      <name>hadoop.proxyuser.root.users</name>
      <value>*</value>
  </property>

  <!-- Dremio requires proxyuser for the dremio user -->
  <property>
    <name>hadoop.proxyuser.dremio.hosts</name>
    <value>*</value>
  </property>
  <property>
    <name>hadoop.proxyuser.dremio.groups</name>
    <value>*</value>
  </property>
  <property>
    <name>hadoop.proxyuser.dremio.users</name>
    <value>*</value>
  </property>

  <property>
    <name>hadoop.ssl.require.client.cert</name>
    <value>false</value>
  </property>
  <property>
    <name>hadoop.ssl.hostname.verifier</name>
    <value>DEFAULT</value>
  </property>
  <property>
    <name>hadoop.ssl.keystores.factory.class</name>
    <value>org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory</value>
  </property>
  <property>
    <name>hadoop.ssl.server.conf</name>
    <value>ssl-server.xml</value>
  </property>
  <property>
    <name>hadoop.ssl.client.conf</name>
    <value>ssl-client.xml</value>
  </property>

</configuration>
' > \$HADOOP_CONF_DIR/core-site.xml"

     Setup the configuration file: /etc/hadoop/conf/ssl-server.xml

     $ cssh "echo '
<configuration>

  <property>
    <name>ssl.server.truststore.location</name>
    <value>/etc/hadoop/conf/pki/certs/truststore.jks</value>
  </property>
  <property>
    <name>ssl.server.truststore.password</name>
    <value>changeme</value>
  </property>
  <property>
    <name>ssl.server.truststore.type</name>
    <value>jks</value>
  </property>
  <property>
    <name>ssl.server.keystore.location</name>
    <value>/etc/hadoop/conf/pki/certs/keystore.jks</value>
  </property>
  <property>
    <name>ssl.server.keystore.password</name>
    <value>changeme</value>
  </property>
  <property>
    <name>ssl.server.keystore.keypassword</name>
    <value>changeme</value>
  </property>
  <property>
    <name>ssl.server.keystore.type</name>
    <value>jks</value>
  </property>

</configuration>
' > \$HADOOP_CONF_DIR/ssl-server.xml"

     Setup the configuration file: /etc/hadoop/conf/ssl-server.xml
     
     $ cssh "echo '
<configuration>

  <property>
    <name>ssl.client.truststore.location</name>
    <value>/etc/hadoop/conf/pki/certs/truststore.jks</value>
  </property>
  <property>
    <name>ssl.client.truststore.password</name>
    <value>changeme</value>
  </property>
  <property>
    <name>ssl.client.truststore.type</name>
    <value>jks</value>
  </property>
  <property>
    <name>ssl.client.keystore.location</name>
    <value>/etc/hadoop/conf/pki/certs/keystore.jks</value>
  </property>
  <property>
    <name>ssl.client.keystore.password</name>
    <value>changeme</value>
  </property>
  <property>
    <name>ssl.client.keystore.keypassword</name>
    <value>changeme</value>
  </property>
  <property>
    <name>ssl.client.keystore.type</name>
    <value>jks</value>
  </property>

</configuration>
' > \$HADOOP_CONF_DIR/ssl-client.xml"

     Setup the configuration file: /etc/hadoop/conf/hdfs-site.xml
     
     $ cssh "echo '
<configuration>

  <property>
    <name>dfs.nameservices</name>
    <value>cluster1</value>
  </property>

  <property>
    <name>dfs.ha.namenodes.cluster1</name>
    <value>nn1,nn2</value>
  </property>

  <property>
    <name>dfs.namenode.rpc-address.cluster1.nn1</name>
    <value>hadoopcluster1namenode1.mydomain.com:8020</value>
  </property>

  <property>
    <name>dfs.namenode.rpc-address.cluster1.nn2</name>
    <value>hadoopcluster1namenode2.mydomain.com:8020</value>
  </property>

  <property>
    <name>dfs.namenode.http-address.cluster1.nn1</name>
    <value>hadoopcluster1namenode1.mydomain.com:50070</value>
  </property>

  <property>
    <name>dfs.namenode.http-address.cluster1.nn2</name>
    <value>hadoopcluster1namenode2.mydomain.com:50070</value>
  </property>
 
  <property>
    <name>dfs.namenode.shared.edits.dir</name>
    <value>qjournal://hadoopcluster1namenode1.mydomain.com:8485;hadoopcluster1namenode2.mydomain.com:8485/cluster1</value>
  </property>

  <property>
    <name>dfs.client.failover.proxy.provider.cluster1</name>
    <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
  </property>

  <property>
      <name>dfs.ha.fencing.methods</name>
      <value>shell(/bin/true)</value>
  </property>

  <property>
    <name>dfs.journalnode.edits.dir</name>
    <value>/home/hadoop/data/journal</value>
  </property>

  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/home/hadoop/data/dfs/name</value>
  </property>

  <property>
    <name>dfs.datanode.data.dir</name>
    <value>/data_1/dfs/data,/data_2/dfs/data,/data_3/dfs/data,/data_4/dfs/data,/data_5/dfs/data,/data_6/dfs/data,/data_7/dfs/data,/data_8/dfs/data,/data_9/dfs/data,/data_10/dfs/data,/data_11/dfs/data,/data_12/dfs/data</value>
  </property>

  <property>
    <name>dfs.replication</name>
    <value>3</value>
  </property>

  <property>
    <name>dfs.permissions</name>
    <value>true</value>
  </property>

  <property>
     <name>dfs.ha.automatic-failover.enabled</name>
     <value>true</value>
   </property>

   <property>
     <name>ha.zookeeper.quorum</name>
     <value>hadoopcluster1namenode1.mydomain.com:2181,hadoopcluster1namenode2.mydomain.com:2181,hadoopcluster1namenode3.mydomain.com:2181</value>
   </property>

<!-- General HDFS security config -->
<property>
  <name>dfs.block.access.token.enable</name>
  <value>true</value>
</property>

<!-- NameNode security config -->
<property>
  <name>dfs.namenode.keytab.file</name>
  <value>/etc/hadoop/conf/hdfs.keytab</value> <!-- path to the HDFS keytab -->
</property>
<property>
  <name>dfs.namenode.kerberos.principal</name>
  <value>hdfs/_HOST@MYDOMAIN.COM</value>
</property>
<property>
  <name>dfs.namenode.kerberos.internal.spnego.principal</name>
  <value>HTTP/_HOST@MYDOMAIN.COM</value>
</property>

<!-- Secondary NameNode security config -->
<property>
  <name>dfs.secondary.namenode.keytab.file</name>
  <value>/etc/hadoop/conf/hdfs.keytab</value> <!-- path to the HDFS keytab -->
</property>
<property>
  <name>dfs.secondary.namenode.kerberos.principal</name>
  <value>hdfs/_HOST@YMYDOMAIN.COM</value>
</property>
<property>
  <name>dfs.secondary.namenode.kerberos.internal.spnego.principal</name>
  <value>HTTP/_HOST@MYDOMAIN.COM</value>
</property>

<!-- DataNode security config -->
<property>
  <name>dfs.datanode.data.dir.perm</name>
  <value>700</value> 
</property>
<property>
  <name>dfs.datanode.address</name>
  <value>0.0.0.0:1004</value>
</property>
<property>
  <name>dfs.datanode.http.address</name>
  <value>0.0.0.0:1006</value>
</property>
<property>
  <name>dfs.datanode.keytab.file</name>
  <value>/etc/hadoop/conf/hdfs.keytab</value> <!-- path to the HDFS keytab -->
</property>
<property>
  <name>dfs.datanode.kerberos.principal</name>
  <value>hdfs/_HOST@MYDOMAIN.COM</value>
</property>

<!-- Web Authentication config -->
<property>
  <name>dfs.web.authentication.kerberos.principal</name>
  <value>HTTP/_HOST@MYDOMAIN.COM</value>
 </property>

<!-- Security for Quorum-based storage (journal nodes) -->
<property>
  <name>dfs.journalnode.keytab.file</name>
  <value>/etc/hadoop/conf/hdfs.keytab</value> <!-- path to the HDFS keytab -->
</property>
<property>
  <name>dfs.journalnode.kerberos.principal</name>
  <value>hdfs/_HOST@MYDOMAIN.COM</value>
</property>
<property>
  <name>dfs.journalnode.kerberos.internal.spnego.principal</name>
  <value>HTTP/_HOST@MYDOMAIN.COM</value>
</property>

<!-- Uncomment this to enable TLS for HDFS (TODO: setup SSL Certs)
<property>
  <name>dfs.http.policy</name>
  <value>HTTPS_ONLY</value>
</property>
-->

</configuration>
' > \$HADOOP_CONF_DIR/hdfs-site.xml"

     Setup the configuration file: /etc/hadoop/conf/hadoop-policy.xml
     
     $ cssh "echo '
<configuration>

<property>
    <name>security.client.protocol.acl</name>
    <value>myuser, hadoopusers</value>
    <description>ACL for ClientProtocol, which is used by user code via the DistributedFileSystem.
</description>
</property>

<property>
    <name>security.job.submission.protocol.acl</name>
    <value>*</value>
    <description>ACL for JobSubmissionProtocol, used by job clients to communciate with the jobtracker for job submission, querying job status etc.
</description>
</property>

</configuration>
' > \$HADOOP_CONF_DIR/hadoop-policy.xml"

     Setup the configuration file: /etc/default/hadoop-hdfs-datanode (needed for secure datanodes)
     
     $ cssh "echo '

export HADOOP_SECURE_DN_USER=hdfs
export HADOOP_SECURE_DN_PID_DIR=/var/lib/hadoop-hdfs
export HADOOP_SECURE_DN_LOG_DIR=/var/log/hadoop-hdfs
export JSVC_HOME=/usr/lib/bigtop-utils/

' > /etc/default/hadoop-hdfs-datanode"

     $ cssh " cat /etc/default/hadoop-hdfs-datanode"

     Setup the configuration file: /etc/hadoop/conf/yarn-site.xml
     
     $cssh "echo '
<configuration>

    <property>
        <name>yarn.acl.enable</name>
        <value>false</value>
    </property>

    <property>
        <name>yarn.resourcemanager.scheduler.class</name>
        <value>org.apache.hadoop.yarn.server.resourcemanager.scheduler.capacity.CapacityScheduler</value>
    </property>

    <property>
      <name>yarn.resourcemanager.ha.enabled</name>
      <value>true</value>
    </property>
    <property>
      <name>yarn.resourcemanager.cluster-id</name>
      <value>cluster1</value>
    </property>
    <property>
      <name>yarn.resourcemanager.ha.rm-ids</name>
      <value>rm1,rm2</value>
    </property>
    <property>
      <name>yarn.resourcemanager.hostname.rm1</name>
      <value>192.168.1.201</value>
    </property>
    <property>
      <name>yarn.resourcemanager.hostname.rm2</name>
      <value>192.168.1.202</value>
    </property>
    <property>
      <name>yarn.resourcemanager.webapp.address.rm1</name>
      <value>192.168.1.201:8088</value>
    </property>
    <property>
      <name>yarn.resourcemanager.webapp.address.rm2</name>
      <value>192.168.1.202:8088</value>
    </property>

    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services.mapreduce_shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>

    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>55000</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.cpu-vcores</name>
        <value>20</value>
    </property>

<property>
  <name>yarn.scheduler.maximum-allocation-mb</name>
  <value>10000</value>
  <description>
  </description>
</property>

<property>
  <name>yarn.scheduler.maximum-allocation-vcores</name>
  <value>6</value>
  <description>
  </description>
</property>

    <property>
        <name>yarn.nodemanager.local-dirs</name>
        <value>/data_1/yarn/data,/data_2/yarn/data,/data_3/yarn/data,/data_4/yarn/data,/data_5/yarn/data,/data_6/yarn/data,/data_7/yarn/data,/data_8/yarn/data,/data_9/yarn/data,/data_10/yarn/data,/data_11/yarn/data,/data_12/yarn/data</value>
    </property>

    <property>
      <name>hadoop.zk.address</name>
      <value>192.168.1.201:2181,192.168.1.202:2181,192.168.1.203:2181</value>
    </property>

</configuration>
' > \$HADOOP_CONF_DIR/yarn-site.xml"

     Setup the configuration file: /etc/hadoop/conf/capacity-scheduler.xml
     
     $ cssh "echo '

<configuration>

<property>
  <name>yarn.scheduler.capacity.root.queues</name>
  <value>default, dremio</value>
  <description>The queues at the this level (root is the root queue).
  </description>
</property>

<property>
  <name>yarn.scheduler.capacity.root.capacity</name>
  <value>100.0</value>
  <description>Float value (Percentage). All must equal 100%
  </description>
</property>

<property>
  <name>yarn.scheduler.capacity.root.default.capacity</name>
  <value>20</value>
  <description>Float value (Percentage). All must equal 100%
  </description>
</property>

<property>
  <name>yarn.scheduler.capacity.root.dremio.capacity</name>
  <value>80</value>
  <description>Float value (Percentage). All must equal 100%
  </description>
</property>

<property>
  <name>yarn.scheduler.capacity.root.dremio.maximum-allocation-mb</name>
  <value>9000</value>
  <description>The maximum allocation for every container request in this queue, in MBs. Memory requests higher than this will throw a InvalidResourceRequestException.
  </description>
</property>

<property>
  <name>yarn.scheduler.capacity.root.dremio.maximum-allocation-vcores</name>
  <value>4</value>
  <description>This is the maximum allocation for every container request at the Resource Manager, in terms of virtual CPU cores. Requests higher than this wont take effect, and will get capped to this value. 
  </description>
</property>

</configuration>

' > \$HADOOP_CONF_DIR/capacity-scheduler.xml"

     Setup the configuration file: /etc/hadoop/conf/mapred-site.xml
     
     $ cssh "echo '

<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>

  <property>
    <name>mapred.system.dir</name>
    <value>file:/home/hadoop/data/mapred/system</value>
    <final>true</final>
  </property>

  <property>
    <name>mapred.local.dir</name>
    <value>file:/home/hadoop/data/mapred/local</value>
    <final>true</final>
  </property>

</configuration>

' > \$HADOOP_CONF_DIR/mapred-site.xml"

     Setup the configuration file: /etc/hadoop/conf/log4j 

     $ cssh "mkdir -p /var/log/hadoop"

     $ cssh "rm /var/lib/hadoop-2.10.0/conf/log4j.properties"

     $ cssh "echo '
# Define some default values that can be overridden by system properties
hadoop.root.logger=INFO,console
hadoop.log.dir=/var/log/hadoop
hadoop.log.file=hadoop.log

# Define the root logger to the system property hadoop.root.logger.
log4j.rootLogger=\${hadoop.root.logger}, EventCounter

# Logging Threshold
log4j.threshold=ALL

# Null Appender
log4j.appender.NullAppender=org.apache.log4j.varia.NullAppender

# Rolling File Appender - cap space usage at 5gb.
hadoop.log.maxfilesize=256MB
hadoop.log.maxbackupindex=20
log4j.appender.RFA=org.apache.log4j.RollingFileAppender
log4j.appender.RFA.File=\${hadoop.log.dir}/\${hadoop.log.file}

log4j.appender.RFA.MaxFileSize=\${hadoop.log.maxfilesize}
log4j.appender.RFA.MaxBackupIndex=\${hadoop.log.maxbackupindex}

log4j.appender.RFA.layout=org.apache.log4j.PatternLayout

' > \$HADOOP_CONF_DIR/log4j.properties"

     Start the Journal Nodes

     $ cssh -n "su -l hdfs -c '$HADOOP_HOME/sbin/hadoop-daemon.sh start journalnode'"
     $ cssh -n "ps -ef |grep journalnode"

     Format the name node on hadoopcluster1namenode1 (one-time only)

     $ cssh -n "mkdir -p /home/hadoop/data/dfs/name"
     $ ssh -i ~/.ssh/id_rsa_cssh root@hadoopcluster1namenode1 "hdfs namenode -format"

     Copy the name node meta data to the second name node (one-time only)

     $ ssh -i ~/.ssh/id_rsa_cssh root@hadoopcluster1namenode2 "hdfs namenode -bootstrapStandby"

     Start the name node daemons on hadoopcluster1namenode1 and hadoopcluster1namenode2 (only 2 namenodes allowed in Hadoop 2.10.0)
    
     $ ssh -i ~/.ssh/id_rsa_cssh root@hadoopcluster1namenode1 "hadoop-daemon.sh start namenode"     
     $ ssh -i ~/.ssh/id_rsa_cssh root@hadoopcluster1namenode2 "hadoop-daemon.sh start namenode"

     Format the Zookeeper store (one-time only)

     $ ssh -i ~/.ssh/id_rsa_cssh root@hadoopcluster1namenode1 "hdfs zkfc -formatZK"

     Start the Hadooop zookeeper client instances

     $ cssh -n "hadoop-daemon.sh start zkfc"

     Start the data node daemons

     $ cssh -d "hadoop-daemon.sh start datanode"   

     See haadmin -help
     See hdfs dfsadmin -report -live
     See hadoop fs -ls /


     Startup the Hadoop Daemons

     $ cssh -n "
zkServer.sh start
hadoop-daemon.sh --script hdfs start zkfc
hadoop-daemon.sh --script hdfs start journalnode
hadoop-daemon.sh --script hdfs start namenode
yarn-daemon.sh start resourcemanager
"
     $ cssh -d "
hadoop-daemon.sh --script hdfs start datanode
yarn-daemon.sh start nodemanager
"

     $ cssh "jps | grep -v Jps | sort -k 2"

     Access the Namenode Consoles

     http://hadoopcluster1namenode1:50070
     http://hadoopcluster1namenode2:50070

     Access the Yarn Console

     http://hadoopcluster1namenode1:8088

     Shutdown Hadoop Daemons

     $ cssh -d "
hadoop-daemon.sh --script hdfs stop datanode
yarn-daemon.sh stop nodemanager
"
     $ cssh -n "
hadoop-daemon.sh --script hdfs stop namenode
hadoop-daemon.sh --script hdfs stop journalnode
yarn-daemon.sh stop resourcemanager
#mr-jobhistory-daemon.sh stop historyserver
hadoop-daemon.sh --script hdfs stop zkfc
zkServer.sh stop
"

     $ cssh "jps | grep -v Jps | sort -k 2"

     Download sample data sets and upload to HDFS

     $ cd $HOME && mkdir -p data-sets && cd data-sets

     San Fransisco Police Dept data - 2003 - 2018 (442M)

     $ curl https://data.sfgov.org/api/views/tmnf-yvry/rows.csv?accessType=DOWNLOAD -o sf-police-2003-2018.txt

     $ hdfs dfs -mkdir -p /sample-data/sf-police
     $ hdfs dfs -copyFromLocal sf-police-2003-2018.txt /sample-data/sf-police/
     $ hdfs dfs -ls -R /sample-data

     Run a test YARN based MapReduce program (on edge node):
     $ yarn jar /var/lib/hadoop-*/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 16 1000

     Convert to user hadoop

     $ cssh "chown -R hadoop:hadoop /var/lib/hadoop-2.10.0"
     $ cssh "chown -R hadoop:hadoop /var/log/hadoop"
     $ cssh -d "chown -R hadoop:hadoop /data_*"
     $ #cssh -d "chmod 700 -R hadoop:hadoop /data_*"

## Step 4. Install Dremio on Hadoop w/ YARN

     SEE: https://docs.dremio.com/deployment/yarn-hadoop.html

     Add the following to the hadoop core-site.xml file.

     <property>
       <name>hadoop.proxyuser.dremio.hosts</name>
       <value>*</value>
     </property>
     <property>
       <name>hadoop.proxyuser.dremio.groups</name>
       <value>*</value>
     </property>
     <property>
       <name>hadoop.proxyuser.dremio.users</name>
       <value>*</value>
     </property>

     Add the following to capacity-scheduler.xml
     <property>
       <name>yarn.scheduler.capacity.root.queues</name>
       <value>default, dremio</value>
       <description>The queues at the this level (root is the root queue).
       </description>
     </property>

     <property>
       <name>yarn.scheduler.capacity.root.capacity</name>
       <value>100.0</value>
       <description>Float value (Percentage). All must equal 100%
       </description>
     </property>

     <property>
       <name>yarn.scheduler.capacity.root.default.capacity</name>
       <value>20</value>
       <description>Float value (Percentage). All must equal 100%
       </description>
     </property>
     
     <property>
       <name>yarn.scheduler.capacity.root.dremio.capacity</name>
       <value>80</value>
       <description>Float value (Percentage). All must equal 100%
       </description>
     </property>

     Create a dremio user

     SEE: https://docs.dremio.com/deployment/standalone/standalone-tarball.html

     $ cssh "groupadd -r dremio"
     $ cssh "useradd -r -g dremio -d /var/lib/dremio -s /sbin/nologin dremio"

     Create the dremio directories

     $ cssh "mkdir -p /opt/dremio"
     $ cssh "mkdir -p /var/run/dremio && chown dremio:dremio /var/run/dremio"
     $ cssh "mkdir -p /var/log/dremio && chown dremio:dremio /var/log/dremio"
     $ cssh "mkdir -p /var/log/dremio && chown dremio:dremio /var/log/dremio"

     Download the community edition of Dremio

     $ curl -O http://download.dremio.com/xxxx

     $ cssh "tar xf dremio-enterprise-*.tar.gz -C /opt/dremio --strip-components=1"
     $ cssh "ln -s /opt/dremio/conf /etc/dremio"
     $ cssh "chown -R dremio:dremio /opt/dremio"

     Copy the Hadoop config files to the Dremio directories

     $ cp \$HADOOP_HOME/etc/hadoop/core-site.xml /etc/dremio/
     $ cp \$HADOOP_HOME/etc/hadoop/hdfs-site.xml /etc/dremio/
     $ cp \$HADOOP_HOME/etc/hadoop/yarn-site.xml /etc/dremio/

     Add dremio env variable to /etc/profile.d scripts

     $ export DREMIO_HOME=/opt/dremio' > /etc/profile.d/dremio_env.sh
     $ echo \$DREMIO_HOME

     Create a dremio meta-data directory on the coordinator node (hadoopcluster1edgenode1)

     $ mkdir -p \$DREMIO_HOME/data && chown dremio:dremio \$DREMIO_HOME/data

     Configure Dremio in dremio.conf

     $ sed -i 'sX\#dist: \"pdfs:\/\/\"\${paths.local}\"/pdfs\"X dist: \"hdfs://cluster1/pdfs\" Xg' /opt/dremio/conf/dremio.conf

     $ sed -i 'sXpaths:Xzookeeper: \"hadoopcluster1namenode1:2181,hadoopcluster1namenode2:2181,hadoopcluster1namenode3:2181\"\n\npaths:Xg' /opt/dremio/conf/dremio.conf

     $ sed -i 'sXexecutor.enabled: trueXexecutor.enabled: true,\n  coordinator.master.embedded-zookeeper.enabled: falseXg' /opt/dremio/conf/dremio.conf

     OR

     $ echo '
zookeeper: \"hadoopcluster1namenode1:2181,hadoopcluster1namenode2:2181,hadoopcluster1namenode3:2181\"

paths: {
  # the local path for dremio to store data.
  local: \${DREMIO_HOME}\"/data\"

  # the distributed path Dremio data including job results, downloads, uploads, etc
   dist: \"hdfs://cluster1/pdfs\"
}

services: {
  coordinator.enabled: true,
  coordinator.master.enabled: true,
  executor.enabled: true,
  coordinator.master.embedded-zookeeper.enabled: false
}
' > /opt/dremio/conf/dremio.conf

     Start up the Dremio Daemons

     Start the Dremio Coordinator (only on hadoopcluster1namenode1)

     $ ssh -i ~/.ssh/id_rsa_cssh hadoopcluster1namenode1 "/opt/dremio/bin/dremio start"

     Access the Dremio Coordinator UI

          http://hadoopcluster1edgenode1:9047

     Remove Dremio

     $ /opt/dremio/bin/dremio stop

     $ rm -rf /opt/dremio && rm -rf /var/log/dremio && rm -rf /etc/dremio && /var/run/dremio


## Question or Comments

Direct any questions or comments to: greg@dremio.com


