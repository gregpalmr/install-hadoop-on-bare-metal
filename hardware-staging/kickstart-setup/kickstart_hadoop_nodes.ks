###################################################################
##
## HADOOP NODE KICKSTART SCRIPT
##
## NOTE: Hardware RAID Setup must be done manually first
##
###################################################################

# This is a fresh install, not an upgrade
install

# Use text mode installer
text

# Get the CentOS packages from the staging server
url --url http://192.168.1.30/repos/centos/7.7/os/x86_64

# US Keyboard
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'

# Set to East Coast Timezone
timezone   America/New_York    --isUtc
# timezone America/Chicago     --isUtc
# timezone America/Denver      --isUtc
# timezone America/Los_Angeles --isUtc

eula --agreed

network --onboot=on  --device enp1s0f0 --mtu=1500 --bootproto=dhcp --noipv6 
network --onboot=off --device enp1s0f1 

authconfig --enableshadow --passalgo=sha512

# root password is changeme
#    Generate the encrypted password with:
#       openssl passwd -1 changeme
#
rootpw --iscrypted $1$6DFnPiED$DNnpY8ThyhnQnyVnI5.yw.

# Password : mesosroot
#rootpw --iscrypted $1$YS5nY$bRFWqKJMUT4pD0C7SnFLK1 

firewall --disabled
selinux  --disabled

services --disabled=NetworkManager

bootloader --location=mbr --driveorder=sda --append="crashkernel=auth rhgb"

# Partition the Disks 
#
%include /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks

# Make sure we reboot into the new system when we are finished
#
reboot

####################  Package Selection #############################
%packages
@base
@core
-*firmware
-iscsi*
-fcoe*
-b43-openfwwf
-efibootmgr
openssh-clients
kernel-firmware
man
bind-utils
sysstat
mlocate
sudo
httpd
traceroute
wget
lynx
tcpdump
nmap
perl
xz
unzip
curl
python

%end

######################### PRE ###################################

%pre --interpreter=/bin/bash --log=/mnt/sysimage/root/kickstart-pre.log
#%pre --log=/mnt/sysimage/root/kickstart-pre.log
(

/usr/bin/mkdir -p /mnt/sysimage/root/hadoop_kickstart/

# Set the ip address of the staging server
STAGING_SVR_IP=192.168.1.30
echo " Using Staging Server IP Address: $STAGING_SVR_IP"

# Get the number of hard drives in this server (Hardware RAID drives will show up as 1 drive)
NUM_OF_DISKS=`fdisk -l | grep -e '^Disk /dev/sd' | wc -l`
echo " Number of hard drives found on this server: $NUM_OF_DISKS"

# Get the amount of physical RAM in this server i.e. 65799825 for 64 GB
RAM_SIZE=`free | grep '^Mem' | awk '{print $2}'`
echo " Amount of RAM found on this server: $RAM_SIZE"

#
# Create a custom partition script based on the number of hard drives present
#
# Currently supports:
#	Master Node: 	3 Hardware RAID drives in front (shows up as 1 drive)
#	Worker Node:	2 Sofware  RAID drives in back, 12 JBOD drives in front

echo " See /root/hadoop_kickstart/partition_disks.ks script for disk partition steps"

if [ "$NUM_OF_DISKS" == 1 ]
then

cat > /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks<<EOF
#!/bin/sh
#
# SCRIPT: partition_disks.ks

### Begin Disk Partitioning - Master Node

# This server has 3 RAID drives (1 logical drive) and 
# is a Master node. Create a very large /var partition 
# for log files, but create small /root and /data partitions 
# since no user applications will run on this node
# Create a small swap partition
# becuase if physical memory is exceeded on a worker node
# performance will be so bad, the Hadoop daemons will go into 
# bad health and another master node will become the leader. 
# So no sense in trying to support virtual memory.

# Remove any previous partitions
clearpart --all

# If the RAID 5 drive is bigger than 2 TB, it is a GPT disk and 
# and not an MBR drive and needs a bioboot
# TODO: add an if statement to test for this
# partition
part biosboot --fstype=biosboot --size=1

# Create a boot partion with 500 MB
part /boot --fstype="xfs" --ondisk=sda --size=500

# Create the pysical volumn that the logical volume will use
part pv.01 --fstype="lvmpv" --ondisk=sda --grow --size=1

# Create a logical parition that grows as needed
volgroup vg0 pv.01

# Create the root parition with 20 GB
logvol / --fstype="xfs" --name=lv_root --vgname=vg0 --grow --size=20480

# Create a swap partition with 32 GB (it is small on purpose, see above)
#logvol swap --fstype="swap" --name=lv_swap --vgname=vg0 --size=32768

# Create a /var parition with 820 GB
#logvol /var --fstype="xfs" -n ftype=1 --name=lv_var --vgname=vg0 --size=839680
logvol /var --fstype="xfs" ftype=1 --name=lv_var --vgname=vg0 --size=839680

# Create the /data parition with 32 GB
logvol /data --fstype="xfs" --name=lv_data --vgname=vg0 --size=32240

### End of Disk Partitioning

EOF

elif [ "$NUM_OF_DISKS" == 5 ]
then

cat > /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks<<EOF
#!/bin/sh
#
# SCRIPT: partition_disks.ks
#
#         4 data drive server (with 1 additional OS drive). 
#	  This is a 4 drive hadoop worker node.
#

# make a mount point for the data volumes
#/bin/mkdir -p /mnt/disks

clearpart --all 

part /boot --fstype=ext4 --asprimary --size=500 
part pv.008002 --grow --size=200 

volgroup vg0 --pesize=4096 pv.008002
logvol /home --fstype=ext4 --name=lv_home --vgname=vg0 --size=500
logvol / --fstype=ext4 --name=lv_root --vgname=vg0 --size=134520
#logvol swap --name=lv_swap --vgname=vg0 --size=16120
logvol /var --fstype=ext4 --name=lv_var --vgname=vg0 --size=153600

part /mnt/disks/data_1 --fstype=ext4 --grow --size=1 --ondisk=sdb
part /mnt/disks/data_2 --fstype=ext4 --grow --size=1 --ondisk=sdc
part /mnt/disks/data_3 --fstype=ext4 --grow --size=1 --ondisk=sdd
part /mnt/disks/data_4 --fstype=ext4 --grow --size=1 --ondisk=sde

### End of Disk Partitioning

EOF

elif [ "$NUM_OF_DISKS" == 14 ] || [ "$NUM_OF_DISKS" == 13 ] # 13 if one raid1 drive is offline
then

# Check if this datanode has a raid1 setup. If not, hard code to use /dev/sdm for OS disk
if [ "$(fdisk -l | grep md126)" != "" ]
then
	OS_DEVICE=md126  # The OS Drive is in RAID mode, use /dev/md126
else
	if [ "$(fdisk -l | grep 'Disk /dev/sda' | grep 500)" != "" ]
	then
		OS_DEVICE=sda    # The OS Drive is in RAID mode, use /dev/sda
	else
		OS_DEVICE=sdm    # The OS Drive is in RAID mode, use /dev/sdm
	fi
fi

cat > /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks<<EOF
#!/bin/sh
#
# SCRIPT: partition_disks.ks

### Begin Disk Partitioning - Worker Node

# This server has 14 drives (2 software RAID drives in the back 
# and 12 JBOD drives in the front). This is a Worker node.
# Create very large /data partitions because data files
# will be stored on these disks. Create a small swap partition
# becuase if physical memory is exceeded on a worker node
# performance will be so bad, the Hadoop daemons will go into 
# bad health and will be black listed. So no sense in trying to
# support virtual memory.
# NOTE: change the raid drive name from md126 to your name

# Remove any previous partition info
clearpart --all

# TODO: Find out why this is needed on c1dn5 (which has 3TB drives instead of 2TB drives)
part biosboot --fstype=biosboot --size=1

# Create a boot partion with 500 MB

# Create the boot partition
part /boot --fstype=xfs --asprimary --size=500 --ondisk=${OS_DEVICE}

# Create a physical parition that grows as needed
part pv.008002 --grow --size=200 --ondisk=${OS_DEVICE}

# Create a logical partition 
volgroup vg0 --pesize=4096 pv.008002

# Create the root parition with 131 GB or more
logvol /     --fstype=xfs --name=lv_root --vgname=vg0 --size=134520 --grow

# Create a swap partition with 16 GB
#logvol swap                --name=lv_swap --vgname=vg0 --size=16120

# Create a /var parition with 150 GB
logvol /var  --fstype=xfs --name=lv_var  --vgname=vg0 --size=153600

# Create a small /home partition with 500 MB
logvol /home --fstype=xfs --name=lv_home --vgname=vg0 --size=500

EOF

#
# create 12 very large /data_?? partitions for data (2 TB to 3 TB)
#

# If this datanode has 3TB drives in it, only partition 2TB of them

if [ "$(fdisk -l | grep 'Disk /dev/sd' | grep 3000)" != "" ]
then
     PART_SIZE=1907348
else
     PART_SIZE=1
fi
     
# If this datanode has a 500 GB drive on /dev/sda, then
# start with /dev/sdb

if [ "$(fdisk -l | grep 'Disk /dev/sda' | grep 500)" != "" ]
then
	cat >> /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks<<EOF
		part /data_1  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdb
		part /data_2  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdc
		part /data_3  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdd
		part /data_4  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sde
		part /data_5  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdf
		part /data_6  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdg
		part /data_7  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdh
		part /data_8  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdi
		part /data_9  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdj
		part /data_10 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdk
		part /data_11 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdl
		part /data_12 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdm
EOF

# If this datanode has a 500 GB drive starting on /dev/sdm, then 
# start with /dev/sda 

elif [ "$(fdisk -l | grep 'Disk /dev/sdm' | grep 500)" != "" ]
then
	cat >> /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks<<EOF
		part /data_1  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sda
		part /data_2  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdb
		part /data_3  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdc
		part /data_4  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdd
		part /data_5  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sde
		part /data_6  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdf
		part /data_7  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdg
		part /data_8  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdh
		part /data_9  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdi
		part /data_10 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdj
		part /data_11 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdk
		part /data_12 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdl
EOF

# Otherwise, start with /dev/sdc

else
	cat >> /mnt/sysimage/root/hadoop_kickstart/partition_disks.ks<<EOF
		part /data_1  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdc
		part /data_2  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdd
		part /data_3  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sde
		part /data_4  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdf
		part /data_5  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdg
		part /data_6  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdh
		part /data_7  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdi
		part /data_8  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdj
		part /data_9  --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdk
		part /data_10 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdl
		part /data_11 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdm
		part /data_12 --fstype=xfs --grow --size=${PART_SIZE} --ondisk=sdn
EOF

fi

### End of Disk Partitioning
fi

#
# Generate a script to convert the network to a static IP address
#

echo " See the /root/hadoop_kickstart/convert_network_to_static_ip.ks script for network setup"

cat > /mnt/sysimage/root/hadoop_kickstart/convert_network_to_static_ip.ks<<EOF
#
# SCRIPT: /root/hadoop_kickstart/convert_network_to_static_ip.ks
#
# Use LACP with 2 1Gig bonded ethernet adapters

# Get the names of the first two network interfaces
i=0
for interface in `ip link | grep -iv loopback | grep -v link | cut -d ':' -f 2 | sed 's/ //g' | tr '\n' ' '`
do
    if [ \$i -eq 0 ]
    then
        echo Setting up INTERFACE_01 as: \$interface
        INTERFACE_01=\$interface
    else
        echo Setting up INTERFACE_02 as: \$interface
        INTERFACE_02=\$interface
        break
    fi
    ((i=i+1))
done

# Get the MAC addresses of the first two network interfaces
i=0
for mac in `ip link | grep ether | awk '{print \$2}' | tr '\n' ' '`
do
    if [ \$i -eq 0 ]
    then
        echo Setting up MAC_01 as: \$mac
        MAC_01=\$mac
    else
        echo Setting up MAC_02 as: \$mac
        MAC_02=\$mac
        break
    fi
    ((i=i+1))
done

# Based on the MAC address, sense what node this is

if [ "\$MAC_01" == "00:25:90:7e:4a:a0" ]     # c1en1
then
    THIS_HOSTNAME="c1en1"
    IP_ADDRESS="192.168.1.206"
    echo " Setting up \$THIS_HOSTNAME "

elif [ "\$MAC_01" == "00:25:90:d0:9b:0e" ]     # c1nn1
then
    THIS_HOSTNAME="c1nn1"
    IP_ADDRESS="192.168.1.201"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:9a:be:8e" ]    # c1nn2
then
    THIS_HOSTNAME="c1nn2"
    IP_ADDRESS="192.168.1.202"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:99:be:84" ]    # c1nn3
then
    THIS_HOSTNAME="c1nn3"
    IP_ADDRESS="192.168.1.203"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:e9:66:b0" ]    # c1dn1
then
    THIS_HOSTNAME="c1dn1"
    IP_ADDRESS="192.168.1.211"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:ca:f9:80" ]    # c1dn2
then
    THIS_HOSTNAME="c1dn2"
    IP_ADDRESS="192.168.1.212"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:ca:f6:9c" ]    # c1dn3
then
    THIS_HOSTNAME="c1dn3"
    IP_ADDRESS="192.168.1.213"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:e8:97:84" ]    # c1dn4
then
    THIS_HOSTNAME="c1dn4"
    IP_ADDRESS="192.168.1.214"
    echo " Setting up \$THIS_HOSTNAME "

elif  [ "\$MAC_01" == "00:25:90:c9:a5:4c" ]    # c1dn5
then
    THIS_HOSTNAME="c1dn5"
    IP_ADDRESS="192.168.1.215"
    echo " Setting up \$THIS_HOSTNAME "
fi

# Shutdown the current network and disable NetworkManager
systemctl stop network
systemctl stop NetworkManager
systemctl disable NetworkManager
yum -y erase NetworkManager*

#cat > /etc/sysconfig/network-scripts/ifcfg-bond0<<EOF_NIC
cat > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-bond0<<EOF_NIC
DEVICE=bond0
NAME=bond0
TYPE=Bond
BONDING_MASTER=yes
IPADDR=\${IP_ADDRESS}
NETMASK=255.255.255.0
ONBOOT=yes
BOOTPROTO=static
USERCTL=no
MTU=9000
BONDING_OPTS="mode=4 miimon=100 lacp_rate=1"
IPV6INIT=no
IPV6_AUTOCONF=no
PEERDNS=yes
GATEWAY=192.168.1.1
DNS1=8.8.8.8
DNS2=8.8.4.4
EOF_NIC

#cat > /etc/sysconfig/network-scripts/ifcfg-\${INTERFACE_01}<<EOF_NIC
cat > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-\${INTERFACE_01}<<EOF_NIC
DEVICE=\${INTERFACE_01}
NAME=\${INTERFACE_01}
USERCTL=no
ONBOOT=yes
MASTER=bond0
SLAVE=yes
BOOTPROTO=none
EOF_NIC

if [ "\$INTERFACE_02" != "" ]
then
#cat > /etc/sysconfig/network-scripts/ifcfg-\${INTERFACE_02}<<EOF_NIC
cat > /mnt/sysimage/etc/sysconfig/network-scripts/ifcfg-\${INTERFACE_02}<<EOF_NIC
DEVICE=\${INTERFACE_02}
NAME=\${INTERFACE_02}
USERCTL=no
ONBOOT=yes
MASTER=bond0
SLAVE=yes
BOOTPROTO=none
EOF_NIC
fi

# end of script
EOF

# Create a script to update the /etc/hosts file
#
echo " See the /root/hadoop_kickstart/modify_etc_hosts_file.ks script for hosts file setup"

cat > /mnt/sysimage/root/hadoop_kickstart/modify_etc_hosts_file.ks<<EOF
#
# SCRIPT: /root/hadoop_kickstart/modify_etc_hosts_file.ks
#
# Add this server ip to the /etc/host file
echo " " >> /mnt/sysimage/etc/hosts

# Add staging server ip to the /etc/host file
echo "# Cluster staging node (for PXE & Kickstart booting)" >> /mnt/sysimage/etc/hosts
echo "$STAGING_SVR_IP     staging1" >> /mnt/sysimage/etc/hosts
echo " " >> /mnt/sysimage/etc/hosts

# Add the other cluster hostnames to the /etc/host file
echo "# Hadoop edge node:" >> /mnt/sysimage/etc/hosts
echo "192.168.1.197 c1en1.local.net c1en1" >> /mnt/sysimage/etc/hosts
echo " " >> /mnt/sysimage/etc/hosts

echo "# Hadoop Namenodes:" >> /mnt/sysimage/etc/hosts
echo "192.168.1.201 c1nn1.local.net c1nn1" >> /mnt/sysimage/etc/hosts
echo "192.168.1.202 c1nn2.local.net c1nn2" >> /mnt/sysimage/etc/hosts
echo "192.168.1.203 c1nn3.local.net c1nn3" >> /mnt/sysimage/etc/hosts
echo " " >> /mnt/sysimage/etc/hosts

echo "# Hadoop Datanodes:" >> /mnt/sysimage/etc/hosts
echo "192.168.1.211 c1dn1.local.net c1dn1" >> /mnt/sysimage/etc/hosts
echo "192.168.1.212 c1dn2.local.net c1dn2" >> /mnt/sysimage/etc/hosts
echo "192.168.1.213 c1dn3.local.net c1dn3" >> /mnt/sysimage/etc/hosts
echo "192.168.1.214 c1dn4.local.net c1dn4" >> /mnt/sysimage/etc/hosts
echo "192.168.1.215 c1dn5.local.net c1dn5" >> /mnt/sysimage/etc/hosts
echo "192.168.1.216 c1dn6" >> /mnt/sysimage/etc/hosts
echo "192.168.1.217 c1dn7" >> /mnt/sysimage/etc/hosts
echo "192.168.1.218 c1dn8" >> /mnt/sysimage/etc/hosts
echo "192.168.1.219 c1dn9" >> /mnt/sysimage/etc/hosts
echo "192.168.1.220 c1dn10" >> /mnt/sysimage/etc/hosts
echo "192.168.1.221 c1dn11" >> /mnt/sysimage/etc/hosts
echo "192.168.1.222 c1dn12" >> /mnt/sysimage/etc/hosts
echo "192.168.1.223 c1dn13" >> /mnt/sysimage/etc/hosts
echo "192.168.1.224 c1dn14" >> /mnt/sysimage/etc/hosts
echo "192.168.1.225 c1dn15" >> /mnt/sysimage/etc/hosts
echo "192.168.1.226 c1dn16" >> /mnt/sysimage/etc/hosts
echo "192.168.1.227 c1dn17" >> /mnt/sysimage/etc/hosts
echo "192.168.1.228 c1dn18" >> /mnt/sysimage/etc/hosts
echo "192.168.1.229 c1dn19" >> /mnt/sysimage/etc/hosts
echo "192.168.1.230 c1dn20" >> /mnt/sysimage/etc/hosts

# Add the gateway to the /etc/sysconfig/network file
cat >/mnt/sysimage/etc/sysconfig/network<<EOF_NET
NETWORKING=yes
GATEWAY=192.168.1.1
EOF_NET

cat >/mnt/sysimage/etc/hostname<<EOF_NET
$THIS_HOSTNAME.local.net
EOF_NET

# end of script
EOF

) 2>&1 >/mnt/sysimage/root/kickstart-pre-sh.log

%end

######################### POST #######################################
%post --nochroot --interpreter=/bin/bash --log=/mnt/sysimage/root/kickstart-post.log
#%post --nochroot --log=/mnt/sysimage/root/kickstart-post.log
(

PATH=/bin:/sbin:/usr/sbin:/usr/sbin
export PATH

# Add the staging1 server ip address to /etc/hosts
#
%include /mnt/sysimage/root/hadoop_kickstart/modify_etc_hosts_file.ks

# add group nogroup 
#groupadd nogroup

# add the clusteradmin user with sudo privs
# clusteradmin password is admin318
#pass=`/usr/bin/perl -e 'print crypt("admin318", "salt"),"\n"'`
pass="sakJDzuKta7Ho"    
useradd -m -u 1020 -p $pass clusteradmin
echo "clusteradmin ALL = NOPASSWD: ALL"   > /tmp/sudoers_clusteradmin
echo 'Defaults:clusteradmin !requiretty' >> /tmp/sudoers_clusteradmin
chown root:root /tmp/sudoers_clusteradmin
chmod 0440 /tmp/sudoers_clusteradmin
mv /tmp/sudoers_clusteradmin /mnt/sysimage/etc/sudoers.d/clusteradmin

# Add the private and public SSH keys for clusteradmin user
mkdir -p /home/clusteradmin/.ssh

# Add the SSH public key to ~/.ssh/authorized_keys

cat > /home/clusteradmin/.ssh/id_rsa <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEoAIBAAKCAQEAqh95Wh7SnqZJZOqJYKQPXIwUN2bnbpjjGRd3mU7/jqUPTinC
+DpA0rw+m34bzizKFrXF2NtgBc0yJZ8PE0fwiO85q/w62GC6guqO5909Z+JBjbTc
lsDHtKdznidij328wnZZrPv4oNMWTpYs0hIEdaqvOD59z81UW3qAM8h3EobUgeh0
NkEDLv8AwbtOzw2SKyBbpYIPGk7+agUSzQDZBtb68IuulV+1aIWmf4xPYB4LQbGU
oL1IgxPadqdAzf2Fo0EVchygzFHs9v/4TXuBhRcry5R+sKjEMPcLbyqqR96T8PA6
5Vhok/TNPb8nqaTI/N/bUWp/oDprnxT279xLmwIBIwKCAQA1d5sq876JofnPQmWw
qJcdFhT7eBzZncO3bcaAo8ypLI/IG8Du7byaAKX2WtWJ8NHMn4dSyJqFewEhxEaR
B/sjuOY9XeabxqEEktx0weAZVbzUw9BMovzvoleJehepcKkJ6q54Me8N+TLlf6ev
vIUPCcIKXMh0glxXQ8HkY5MjE+snr6TwsNSaWEwNj1JimDRi6MNrUflaXBiT2XFT
tdhWLfqWpX94qeTinbiIBQAqb1pWsJw1+j/PVltJfyB6EtMvI9RVKVUGJDKc09y1
io2XQisiCf3En79qEjHw2OZxyrwUT7a4fR0turIYLsYkcWDsTEB2oc3C0dFYGWJZ
VLpbAoGBAOBRrax7bWdXTirJWmc0rErxgh3V6sooj5MpP0gLumTq0Cw/n0YLHbGp
u14A7TQQuPFRTRShuzjuGOTwl45w8i8F/yTg6CTJvSBGor2b3CRPJEfjy5LOLRFa
JDgOCTPKxmKSMYTZNCMQfUatEmdL5f5G+0djn4eunefLLvUjhP4jAoGBAMImUbrr
ibGPgJ4qUxADlENzRURi2ELSPUuY42IrSax+LrFdOuo435/Wd1pwvb2xGhHFSdTH
n/67c9MQknmSz3DYuKoN34TAfrdJAPDNFQ8O2ok1qSGIIlHLJJGRWA2eqmaSe0Ie
ORc3yGcsdQQYVgquw2m6JTq0Rrsv8lSBj4gpAoGAc100vxrnzr8vg7gCm3osuNP5
xjOAEDId8+lTvqbyJUWPobpR6YIPRW07yfHZE3ZQfBsu9Krykk6Qdb2PxZksGC74
PtoQ/PoJflA2cCRFVIB5DwdwAltnooYhQWZN4B8kMrGVz0siIKlk/8a5AeyE6SvR
r6+T32EeAi365Hiqy9cCgYBIHNyHQYrqLfyShL/EHpYnrnjQQfiN2Q9z2bOK3ODZ
qzXqG1BloBiL01DnE+60K9Z7oQzLYBba9SsFQKtu/APoFftyXOyfBatophZKz9Sf
MWcdBU1y2srrLjIncH/Ki2Pc9JQugEEXQJrkfjoXdsDfZXvILzJmQvWzPbHHndY5
4wKBgF1sjWAL1LAJbvrvGfRi6f56yYxv0bV8boKAQSHYDW+PSglrr1uml4PeZj76
c/T1m5Wl0oNInGtNvfJ++AFZA81PhsL3NBlVCUFfJp/FDaHZD1ZL1KUEcVq1lQ9E
jBhZafv+10jpsbBxVN1QvAUirPQh1ZTnosPW3e2tS0jUZ+oI
-----END RSA PRIVATE KEY-----
EOF

cat > /home/clusteradmin/.ssh/id_rsa.pub <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAqh95Wh7SnqZJZOqJYKQPXIwUN2bnbpjjGRd3mU7/jqUPTinC+DpA0rw+m34bzizKFrXF2NtgBc0yJZ8PE0fwiO85q/w62GC6guqO5909Z+JBjbTclsDHtKdznidij328wnZZrPv4oNMWTpYs0hIEdaqvOD59z81UW3qAM8h3EobUgeh0NkEDLv8AwbtOzw2SKyBbpYIPGk7+agUSzQDZBtb68IuulV+1aIWmf4xPYB4LQbGUoL1IgxPadqdAzf2Fo0EVchygzFHs9v/4TXuBhRcry5R+sKjEMPcLbyqqR96T8PA65Vhok/TNPb8nqaTI/N/bUWp/oDprnxT279xLmw== clusteradmin
EOF

cat > /home/clusteradmin/.ssh/authorized_keys <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAqh95Wh7SnqZJZOqJYKQPXIwUN2bnbpjjGRd3mU7/jqUPTinC+DpA0rw+m34bzizKFrXF2NtgBc0yJZ8PE0fwiO85q/w62GC6guqO5909Z+JBjbTclsDHtKdznidij328wnZZrPv4oNMWTpYs0hIEdaqvOD59z81UW3qAM8h3EobUgeh0NkEDLv8AwbtOzw2SKyBbpYIPGk7+agUSzQDZBtb68IuulV+1aIWmf4xPYB4LQbGUoL1IgxPadqdAzf2Fo0EVchygzFHs9v/4TXuBhRcry5R+sKjEMPcLbyqqR96T8PA65Vhok/TNPb8nqaTI/N/bUWp/oDprnxT279xLmw== clusteradmin
EOF

chown -R clusteradmin:clusteradmin /home/clusteradmin
chmod u+rwx /home/clusteradmin/.ssh
chmod 400 /home/clusteradmin/.ssh/*

#
# Create a yum.repos.d file that points to the local yum repo
#

cp /mnt/sysimage/etc/yum.repos.d/CentOS-Base.repo /mnt/sysimage/etc/yum.repos.d/CentOS-Base.repo.orig
cat > /mnt/sysimage/etc/yum.repos.d/CentOS-Base.repo.new<<EOF
# CentOS-Base.repo
#
[base]
name=CentOS-\$releasever - Base
baseurl=http://staging1/repos/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#released updates 
[updates]
name=CentOS-\$releasever - Updates
baseurl=http://staging1/repos/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that may be useful
[extras]
name=CentOS-\$releasever - Extras
baseurl=http://staging1/repos/centos/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-\$releasever - Plus
baseurl=http://staging1/repos/centos/\$releasever/centosplus/\$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

EOF

#
# Add the EPEL yum.repos.d file
#

cp /mnt/sysimage/etc/yum.repos.d/epel.repo /mnt/sysimage/etc/yum.repos.d/epel.repo.orig

cat > /mnt/sysimage/etc/yum.repos.d/epel.repo<<EOF
# epel.repo
#
[epel]
name=Extra Packages for Enterprise Linux 7 - \$basearch
baseurl=http://staging1/repos/epel/7/\$basearch
failovermethod=priority
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

[epel-debuginfo]
name=Extra Packages for Enterprise Linux 7 - \$basearch - Debug
baseurl=http://staging1/repos/epel/7/\$basearch/debug
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
gpgcheck=1

[epel-source]
name=Extra Packages for Enterprise Linux 7 - \$basearch - Source
baseurl=http://staging1/repos/epel/7/SRPMS
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
gpgcheck=1

EOF

# Turn off SELinux
#
sed -i 's/SELINUX=enforcing/SELINUX=disabled' /mnt/sysimage/etc/selinux/config 

# Clean out the yum cache
yum clean all

# Setup the static network ip address
#
%include /mnt/sysimage/root/hadoop_kickstart/convert_network_to_static_ip.ks

# Add nogroup to cluster node for Mesos use
groupadd nogroup

# Update all the packages
#
yum -y update

# Download the Hadoop 2.10.0 tarball to this host
curl -O http://staging1/repos/hadoop/2.10.0/hadoop-2.10.0.tar.gz
tar -xvf hadoop-2.10.0.tar.gz -C /mnt/sysimage/var/lib/hadoop-2.10.0
ln -s /mnt/sysimage/var/lib/hadoop-2.10.0 /mnt/sysimage/var/lib/hadoop

) 2>&1 >/mnt/sysimage/root/kickstart-post-sh.log

%end
