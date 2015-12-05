# Kickstart file
# ks-bd.ks (basic server minimal desktop)
# Objective: (Mostly) unattend install of Oracle Linux 6u7
#            On start, hostame, IP-Address, subnet mask and gateway are
#            requested in interactive mode.
# Result:    Oracle Linux with users and groups oracle (g_fmw)
#            Group vboxsf assigned to user oracle
#	           Password foor root, oracle and dba set as "welcome1"
#            Directory ownership/structure oracle:g_fmw /u01/app
#            Install RPM oracle-rdbms-server-11gR2-preinstall
#            Install RPM oracle-rdbms-server-12cR1-preinstall
#	           Install Virtual Box Additions
#

# Uncomment next line if Desktop should be started on boot
xconfig --startxonboot

text
install
cdrom
lang en_US.UTF-8
keyboard us
reboot
network --onboot no --device eth0 --bootproto dhcp --noipv6
rootpw welcome1
firewall --service=ssh
authconfig --enableshadow --passalgo=sha512
selinux --disabled
timezone --utc Europe/Amsterdam
bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet"

# Remove all partitions
zerombr yes
clearpart --initlabel --all
# Create boot partition
part /boot --fstype=ext4 --size=500
# Create partition using all remaining diskspace
part pv.008002 --grow --size=1
# Create volumegroup vg_pvm with logicavolumes lv_root and swap
volgroup vg_pvm --pesize=4096 pv.008002
logvol / --fstype=ext4 --name=lv_root --vgname=vg_pvm --grow --size=1024
logvol swap --name=lv_swap --vgname=vg_pvm --grow --size=16384 --maxsize=16384

%pre
# Switch to 6th console
exec < /dev/tty6 > /dev/tty6 2> /dev/tty6
chvt 6

## Request parameters and store those for POST section
> /tmp/vars
declare -a vararr=("HOSTNAME#localhost" "IPADDRESS#10.20.0.1" "PREFIX#8" "GATEWAY#10.0.0.2" "DNS1#10.0.0.1")
confirmed="no"
while [ ${confirmed} = "no" ]
do
  for index in ${!vararr[*]}
  do
    arrval=${vararr[$index]}
    variable=`echo $arrval | cut -d'#' -f1`
    def=`echo $arrval | cut -d'#' -f2`

    read -p "$variable ($def): " -e value
    if [ ! -n "$value" ]
    then
      value="$def"
    fi

    vararr[$index]="${variable}#${value}"
    eval ${variable}=$value
  done

  echo "Validate settings:"
  confirmed="yes"
  for arrval in "${vararr[@]}"
  do
    variable=`echo $arrval | cut -d'#' -f1`
    printf "%-15s = %s\n" $variable ${!variable}
  done

  read -p "All ok [${confirmed}]:" -e confirmed
  if [ ! -n "$confirmed" ]
  then
    confirmed="yes"
  fi

done

# write values in /tmp/vars to be processed by post section
for index in ${!vararr[*]}
do
  arrval=${vararr[$index]}
  variable=`echo $arrval | cut -d'#' -f1`
  value=`echo $arrval | cut -d'#' -f2`
  echo ${variable}:${value} >> /tmp/vars
done

# Then switch back to Anaconda on the first console
chvt 1
exec < /dev/tty1 > /dev/tty1 2> /dev/tty1
%end

%packages
# ks-mss.ks base packages
@base
@compat-libraries
@client-mgmt-tools
@console-internet
@core
@debugging
@directory-client
@hardware-monitoring
# @java-platform
@large-systems
@network-file-system-client
@performance
@perl-runtime
@server-platform
@server-policy
mtools
pax
python-dmidecode
oddjob
sgpio
device-mapper-persistent-data
samba-winbind
certmonger
pam_krb5
krb5-workstation
perl-DBD-SQLite
# remove these packages if no desktop is necessary
@basic-desktop
@desktop-platform
@fonts
@x11
@development
@internet-browser
%end

%post --nochroot
# Get variables file from pre section
cp /tmp/vars /mnt/sysimage/tmp # /mnt/sysimage/tmp is /tmp in chrooted env
# Copy parallels tools iso image from install iso to chroot /tmp folder
# cp /mnt/source/Parallels/prl-tools-lin.iso /mnt/sysimage/tmp
# Copy VirtualBox guest additions iso image from install iso to chroot /tmp folder
cp /mnt/source/vboxadditions/VBoxGuestAdditions.iso /mnt/sysimage/tmp
%end

%post --log=/root/post-config.log
# Switch to 6th console
exec < /dev/tty6 > /dev/tty6 2> /dev/tty6
chvt 6

#### default groups and users
####
####
#### groups:      g_fmw
#### Users:       oracle
####
####
/usr/sbin/useradd oracle
/usr/sbin/groupadd g_fmw
/usr/sbin/usermod -g g_fmw oracle
echo welcome1 | /usr/bin/passwd --stdin oracle
/bin/mkdir -p /u01/app
/bin/chown -R oracle:g_fmw /u01/app
/bin/mkdir -p /u01/data
/bin/chown -R oracle:g_fmw /u01/data

## Virtualbox users
/usr/sbin/groupadd vboxsf
usermod -a -G vboxsf oracle

## Read variables from PRE section
LIST=$(cat /tmp/vars)
echo $LIST
while read var
do
  varname=`echo $var|cut -d':' -f1`
  varval=`echo $var|cut -d':' -f2`
  export $varname=$varval
done <<< "$LIST"

## Change network configuration
## Change hostname
/bin/sed --in-place 's#localhost\.\(.*\)#'${HOSTNAME}'.\1#' /etc/sysconfig/network
## Change network config
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE=eth0
TYPE=Ethernet
BOOTPROTO=none
IPADDR=${IPADDRESS}
PREFIX=${PREFIX}
GATEWAY=${GATEWAY}
DNS1=${DNS1}
DEFROUTE=yes
IPV4_FAILURE_FATAL=yes
IPV6INIT=no
NAME=eth0
ONBOOT=yes
EOF

/etc/init.d/network restart
/bin/sleep 5
## Update hosts file
echo `/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 \
| awk '{ print $1}'` ${HOSTNAME} ${HOSTNAME}.localdomain >> /etc/hosts

## give all users in group wheel sudo right with NOPASSWD
echo ## Assign SUDO privileges
/bin/sed --in-place 's/#\s\(%wheel\s*ALL=(ALL)\s*NOPASSWD:\sALL\)/\1/' /etc/sudoers
usermod -a -G wheel oracle

## Disable SELinux
echo ## Disable SELinux
/bin/sed --in-place 's#SELINUX=enforcing#SELINUX=disabled#' /etc/selinux/config

## Install oracle-rdbms-server-11gR2-preinstall
sed --in-place "s#\[main\]#\[main\]\nretries=0\ntimeout=60\n#" /etc/yum.conf
cd /etc/yum.repos.d
mv public-yum-ol6.repo public-yum-ol6.repo.vanilla

## retry until successful to workaround "[Errno 14] PYCURL ERROR 56"
successful=1
while [[ ! $successful = 0 ]]
do
  wget http://public-yum.oracle.com/public-yum-ol6.repo
  successful=$?
done

successful=1
while [[ ! $successful = 0 ]]
do
 # /usr/bin/yum -c /etc/yum.conf --assumeyes install oracle-rdbms-server-11gR2-preinstall
  /usr/bin/yum -c /etc/yum.conf --assumeyes install oracle-rdbms-server-12cR1-preinstall
  successful=$?
done

successful=1
while [[ ! $successful = 0 ]]
do
  /usr/bin/yum -c /etc/yum.conf --assumeyes update
  successful=$?
done

## Disable firewall
/sbin/chkconfig iptables off

## Disable unused services
chkconfig --levels 345 abrtd off
chkconfig --levels 345 acpid off
chkconfig --levels 345 atd off
chkconfig --levels 345 auditd off
chkconfig --levels 345 cpuspeed off
chkconfig --levels 345 cups off
chkconfig --levels 345 firstboot off
chkconfig --levels 345 ip6tables off
chkconfig --levels 345 kdump off
chkconfig --levels 345 mdmonitor off
chkconfig --levels 345 postfix off
chkconfig --levels 345 smartd off
chkconfig --levels 345 rhnsd off
chkconfig --levels 345 sssd off
chkconfig --levels 345 wpa_supplicant off
chkconfig --levels 345 ypbind off

### VirtualBox additions install
## Install VirtualBox additions on first boot
cat > /root/install_vboxadditions.sh <<EOF
/bin/sed --in-place 's#/root/install_vboxadditions\.sh.*##' /etc/rc*.d/*.local
mkdir /tmp/vboxadditions
/bin/mount -o loop /tmp/VBoxGuestAdditions.iso /tmp/vboxadditions
cd /tmp/vboxadditions
./VBoxLinuxAdditions.run install
cd /tmp
/bin/umount -f /tmp/vboxadditions
/bin/sed --in-place "s#^/usr/bin/zenity.*##g" /etc/gdm/Init/Default

## Disable screensaver
gconftool-2 -s /apps/gnome-screensaver/idle_activation_enabled --type=bool false

shutdown -r now Restarting
EOF

chmod u+x /root/install_vboxadditions.sh
echo "/root/install_vboxadditions.sh & 2>&1 >> /tmp/vboxadditions_inst.log" >> /etc/rc.local
/bin/sed --in-place "s#\(exit 0\)#/usr/bin/zenity --info --width=400 --height=100 --title=\"Hey there\" --text=\"Hi There!\\\\n\\\\nPlease wait a moment.\\\\n\\\\nI am making the finishing touches and will need to reboot shortly.\\\\n\"\n\n\1#" /etc/gdm/Init/Default


# You can switch back to Anaconda on the first console by
# uncommenting the following two lines
#chvt 1
#exec < /dev/tty1 > /dev/tty1 2> /dev/tty1

reboot

%end
