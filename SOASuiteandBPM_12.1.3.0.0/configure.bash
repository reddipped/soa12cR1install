#!/bin/bash

##
## - create setUserOverrides.sh 
## - disable derby DB
## - prefer IPv4 stack
##
change_domainenv_settings() {

    echo '  - CHANGE DERBY FLAG'
    sed -i -e '/DERBY_FLAG="true"/ s:DERBY_FLAG="true":DERBY_FLAG="false":' ${DOMAIN_HOME}/bin/setDomainEnv.sh

    echo '  - CREATE SETUSEROVERRIDES.SH'
    touch ${DOMAIN_HOME}/bin/setUserOverrides.sh
    chmod u+x ${DOMAIN_HOME}/bin/setUserOverrides.sh

cat > ${DOMAIN_HOME}/bin/setUserOverrides.sh <<SUO_EOF
#!/bin/sh

ADMIN_SERVER_MEM_ARGS="-Xms768m -Xmx768m -XX:MaxPermSize=384m"
SOA_SERVER_MEM_ARGS="-Xms1536m -Xmx2560m -XX:MaxPermSize=1536m"
BAM_SERVER_MEM_ARGS="-Xms1024m -Xmx1024m -XX:MaxPermSize=512m"
OSB_SERVER_MEM_ARGS="-Xms1024m -Xmx1024m -XX:MaxPermSize=512m"
COHERENCE_SERVER_MEM_ARGS="-Xms128m -Xmx128m"

if [ "\${ADMIN_URL}" = "" ] ; then
    USER_MEM_ARGS="\${ADMIN_SERVER_MEM_ARGS}"
else
    case \${SERVER_NAME} in
        soa_server*)
            USER_MEM_ARGS="\${SOA_SERVER_MEM_ARGS}"
        ;;
        bam_server*)
            USER_MEM_ARGS="\${BAM_SERVER_MEM_ARGS}"
        ;;
        osb_server*)
            USER_MEM_ARGS="\${OSB_SERVER_MEM_ARGS}"
        ;;
    esac
fi
export USER_MEM_ARGS

## Prefer IP4v4 stack
EXTRA_JAVA_PROPERTIES="-Djava.net.preferIPv4Stack=true \${EXTRA_JAVA_PROPERTIES}"
export EXTRA_JAVA_PROPERTIES

SUO_EOF

chmod ug+x ${DOMAIN_HOME}/bin/setUserOverrides.sh

}

##
## - starts domain creation and configuration wlst script
##
create_domain() {
    #. ${WL_HOME}/server/bin/setWLSEnv.sh 2>/dev/null 1>&2
    #${JAVA_HOME}/bin/java -Xms2048m -Xmx2048m weblogic.WLST -skipWLSModuleScanning -loadProperties ${CONFIG_BASE}/${DOMAIN_NAME}.properties ./create_domain.py | tail -n +8

    ${WL_HOME}/common/bin/wlst.sh  -skipWLSModuleScanning -loadProperties ${CONFIG_BASE}/${DOMAIN_NAME}.properties ./configure.wlst | tail -n +8
}

##
## Create sufficient entropy during session this session and make if persistent over after booting
##
create_sufficient_entropy() { 

    sudo -s sed --in-place "s#^\(EXTRAOPTIONS=\).*#\1\"-i -r /dev/urandom -o /dev/random -b -t 60 -W 2048\"#" /etc/sysconfig/rngd
    sudo -s rngd -r /dev/urandom -o /dev/random -b 
}

##
## - adds managed server stop/start scripts to linux application menu
##
create_server_control_menu_item() {

  export MANAGED_SERVERNAME=$1 

  echo "  - CREATE MENU ITEMS FOR SERVER ${MANAGED_SERVERNAME}"

  ## Startscript
  cat > ${user_homedir}/Oracle/start_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.sh <<EOFSAS
  #!/bin/bash

  ## Start Script Server
  ${WL_HOME}/common/bin/wlst.sh -loadProperties ${CONFIG_BASE}/${DOMAIN_NAME}.properties ${user_homedir}/Oracle/server_control_${DOMAIN_NAME}.py start ${MANAGED_SERVERNAME} 2>&1 >${CONFIG_BASE}/TMP/start_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.out &
  sleep 2
  echo 'Starting ${MANAGED_SERVERNAME} for domain '${DOMAIN_NAME}
  tail -F ${CONFIG_BASE}/TMP/start_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.out | while read LOGLINE
  do
   [[ "\${LOGLINE}" == *"Successfully started server ${MANAGED_SERVERNAME}"* ]] && pkill -P \$\$ tail
   [[ "\${LOGLINE}" == *"Managed Server already RUNNING"* ]] && pkill -P \$\$ tail
   echo -en ">"
  done
  echo '-'
  echo 'Started ${MANAGED_SERVERNAME} for domain '${DOMAIN_NAME}
  sleep 10
EOFSAS

  chmod ugo+x ${user_homedir}/Oracle/start_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.sh

  ## Desktop Link Startscript
  sudo -E bash -c 'cat > /usr/share/applications/start_${MANAGED_SERVERNAME}_${DOMAIN_NAME}.desktop <<EOF
  #!/usr/bin/env xdg-open

  [Desktop Entry]
  Version=1.0
  Type=Application
  Terminal=true
  Icon[en_US]=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
  Name[en_US]=Start_${MANAGED_SERVERNAME}_${DOMAIN_NAME}
  Exec=gnome-terminal --title "Start_${DOMAIN_NAME}_server_1" -e "${user_homedir}/Oracle/start_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.sh"
  Name=${MANAGED_SERVERNAME}
  Icon=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
  Categories=FusionMiddleware
EOF'


  ## Stop Script 
cat > ${user_homedir}/Oracle/stop_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.sh <<EOFSAS
  #!/bin/bash

  ## Stop Script ${MANAGED_SERVERNAME}
  ${WL_HOME}/common/bin/wlst.sh -loadProperties ${CONFIG_BASE}/${DOMAIN_NAME}.properties ${user_homedir}/Oracle/server_control_${DOMAIN_NAME}.py stop  ${MANAGED_SERVERNAME} 2>&1 >${CONFIG_BASE}/TMP/stop_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.out &
  sleep 2
  echo 'Stopping ${MANAGED_SERVERNAME} for domain '${DOMAIN_NAME}
  #tail -F ${DOMAIN_HOME}/servers/server_1/logs/${MANAGED_SERVERNAME}.out | while read LOGLINE
  tail -F ${CONFIG_BASE}/TMP/stop_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.out | while read LOGLINE
  do
   [[ "\${LOGLINE}" == *"Successfully killed server ${MANAGED_SERVERNAME}"* ]] && pkill -P \$\$ tail
   [[ "\${LOGLINE}" == *"Managed Server already STOPPED"* ]] && pkill -P \$\$ tail
   echo -en ">"
  done
  echo '-'
  echo 'Stopped ${MANAGED_SERVERNAME} for domain '${DOMAIN_NAME}
  sleep 10
EOFSAS

  chmod ugo+x ${user_homedir}/Oracle/stop_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.sh

  ## Desktop Link Stopscript
sudo -E bash -c 'cat > /usr/share/applications/stop_${MANAGED_SERVERNAME}_${DOMAIN_NAME}.desktop <<EOF
  #!/usr/bin/env xdg-open

  [Desktop Entry]
  Version=1.0
  Type=Application
  Terminal=true
  Icon[en_US]=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
  Name[en_US]=Stop_${MANAGED_SERVERNAME}_${DOMAIN_NAME}
  Exec=gnome-terminal --title "Stop_${DOMAIN_NAME}_${MANAGED_SERVERNAME}" -e "${user_homedir}/Oracle/stop_${DOMAIN_NAME}_${MANAGED_SERVERNAME}.sh"
  Name=${MANAGED_SERVERNAME}
  Icon=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
  Categories=FusionMiddleware
EOF'

}

##
## - adds nodemanager stop/start scripts to linux application menu
##
create_nodemanager_control_menu_item() {

echo "  - CREATE NODEMANAGER CONTROL MENU ITEMS"

## Startscript
cat > ${user_homedir}/Oracle/start_${DOMAIN_NAME}_NodeManager.sh <<EOFSAS
#!/bin/bash
cd ${DOMAIN_HOME}/bin
nohup ./startNodeManager.sh 2>&1 >${CONFIG_BASE}/TMP/start_${DOMAIN_NAME}_NodeManager.out &
sleep 2
echo 'Starting NodeManager for domain '${DOMAIN_NAME}
tail -f ${CONFIG_BASE}/TMP/start_${DOMAIN_NAME}_NodeManager.out | while read LOGLINE
do
   [[ "\${LOGLINE}" == *"Plain socket listener started on port"* ]] && pkill -P \$\$ tail
   [[ "\${LOGLINE}" == *"NodeManager process is already running"* ]] && pkill -P \$\$ tail

   echo -en ">"
done
echo '-'
echo 'Started NodeManager for domain '${DOMAIN_NAME}
sleep 5
EOFSAS

chmod ugo+x ${user_homedir}/Oracle/start_${DOMAIN_NAME}_NodeManager.sh

## Desktop Link Startscript
sudo -E bash -c 'cat > /usr/share/applications/Start_NodeManager_${DOMAIN_NAME}.desktop <<EOF
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Terminal=true
Icon[en_US]=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Name[en_US]=Start_NodeManager_${DOMAIN_NAME}
Exec=gnome-terminal --title "start_${DOMAIN_NAME}_NodeManager" -e "${user_homedir}/Oracle/start_${DOMAIN_NAME}_NodeManager.sh 2>&1 &" echo NodeManager is starting ; sleep 5
Name=JDeveloper
Icon=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Categories=FusionMiddleware
EOF'
#chmod ugo+x ~/Desktop/Start_NodeManager_${DOMAIN_NAME}.desktop
#

## Stopscript
cat > ${user_homedir}/Oracle/stop_${DOMAIN_NAME}_NodeManager.sh <<EOFSAS
#!/bin/bash
cd ${DOMAIN_HOME}/bin
echo 'Stopping NodeManager for domain '${DOMAIN_NAME}
ps -ef | grep -i NodeManager | grep -i "domains/${DOMAIN_NAME}/config" | awk '{ print "kill " \$2 }'|bash
nodemgr_inst=1
while [[ "\${nodemgr_inst}" != "0" ]] ; do
   nodemgr_inst=\$(ps -ef | grep -i NodeManager | grep -i "domains/${DOMAIN_NAME}/config" | wc -l)
   sleep 1
   echo -en ">"
done
echo '-'
echo 'Stopped NodeManager for domain '${DOMAIN_NAME}
sleep 5
EOFSAS

chmod ugo+x ${user_homedir}/Oracle/stop_${DOMAIN_NAME}_NodeManager.sh

## Desktop Link Stopscript
sudo -E bash -c 'cat > /usr/share/applications/Stop_NodeManager_${DOMAIN_NAME}.desktop <<EOF
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Terminal=true
Icon[en_US]=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Name[en_US]=Stop_NodeManager_${DOMAIN_NAME}
Exec=gnome-terminal --title "stop_${DOMAIN_NAME}_NodeManager" -e "${user_homedir}/Oracle/stop_${DOMAIN_NAME}_NodeManager.sh 2>&1 &" echo NodeManager is starting ; sleep 5
Name=JDeveloper
Icon=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Categories=FusionMiddleware
EOF'
#chmod ugo+x ~/Desktop/Stop_NodeManager_${DOMAIN_NAME}.desktop

}

create_adminserver_control_menu_item() {

echo "  - CREATE ADMINSERVER CONTROL MENU ITEMS"

## Startscript
cat > ${user_homedir}/Oracle/start_${DOMAIN_NAME}_AdminServer.sh <<EOFSAS
#!/bin/bash

## Start Script AdminServer
${WL_HOME}/common/bin/wlst.sh -loadProperties ${CONFIG_BASE}/${DOMAIN_NAME}.properties ${user_homedir}/Oracle/server_control_${DOMAIN_NAME}.py start  AdminServer 2>&1 >${CONFIG_BASE}/TMP/start_${DOMAIN_NAME}_AdminServer.out &
sleep 2
echo 'Starting AdminServer for domain '${DOMAIN_NAME}
#tail -F ${DOMAIN_HOME}/servers/AdminServer/logs/AdminServer.out | while read LOGLINE
tail -F ${CONFIG_BASE}/TMP/start_${DOMAIN_NAME}_AdminServer.out | while read LOGLINE
do
   [[ "\${LOGLINE}" == *"Successfully started server AdminServer"* ]] && pkill -P \$\$ tail
   [[ "\${LOGLINE}" == *"Managed Server already RUNNING"* ]] && pkill -P \$\$ tail
   echo -en ">"
done
echo '-'
echo 'Started AdminServer for domain '${DOMAIN_NAME}
sleep 10
EOFSAS

chmod ugo+x ${user_homedir}/Oracle/start_${DOMAIN_NAME}_AdminServer.sh

## Desktop Link Startscript
sudo -E bash -c 'cat > /usr/share/applications/start_AdminServer_${DOMAIN_NAME}.desktop <<EOF
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Terminal=true
Icon[en_US]=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Name[en_US]=Start_AdminServer_${DOMAIN_NAME}
Exec=gnome-terminal --title "Start_${DOMAIN_NAME}_AdminServer" -e "${user_homedir}/Oracle/start_${DOMAIN_NAME}_AdminServer.sh"
Name=AdminServer
Icon=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Categories=FusionMiddleware
EOF'
#chmod ugo+x ~/Desktop/start_AdminServer_${DOMAIN_NAME}.desktop
#

## Stop Script AdminServer
cat > ${user_homedir}/Oracle/stop_${DOMAIN_NAME}_AdminServer.sh <<EOFSAS
#!/bin/bash

## Stop Script AdminServer
${WL_HOME}/common/bin/wlst.sh -loadProperties ${CONFIG_BASE}/${DOMAIN_NAME}.properties ${user_homedir}/Oracle/server_control_${DOMAIN_NAME}.py stop  AdminServer 2>&1 >${CONFIG_BASE}/TMP/stop_${DOMAIN_NAME}_AdminServer.out &
sleep 2
echo 'Stopping AdminServer for domain '${DOMAIN_NAME}
#tail -F ${DOMAIN_HOME}/servers/AdminServer/logs/AdminServer.out | while read LOGLINE
tail -F ${CONFIG_BASE}/TMP/stop_${DOMAIN_NAME}_AdminServer.out | while read LOGLINE
do
   [[ "\${LOGLINE}" == *"Successfully killed server AdminServer"* ]] && pkill -P \$\$ tail
   [[ "\${LOGLINE}" == *"Managed Server already STOPPED"* ]] && pkill -P \$\$ tail
   echo -en ">"
done
echo '-'
echo 'Stopped AdminServer for domain '${DOMAIN_NAME}
sleep 10
EOFSAS

chmod ugo+x ${user_homedir}/Oracle/stop_${DOMAIN_NAME}_AdminServer.sh

## Desktop Link Stopscript
sudo -E bash -c 'cat > /usr/share/applications/stop_AdminServer_${DOMAIN_NAME}.desktop <<EOF
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Terminal=true
Icon[en_US]=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Name[en_US]=Stop_AdminServer_${DOMAIN_NAME}
Exec=gnome-terminal --title "Stop_${DOMAIN_NAME}_AdminServer" -e "${user_homedir}/Oracle/stop_${DOMAIN_NAME}_AdminServer.sh"
Name=AdminServer
Icon=$MW_HOME/wlserver/server/lib/consoleapp/webapp/framework/skins/wlsconsole/images/OracleLogo.png
Categories=FusionMiddleware
EOF'


}

##
## Set environment variables
##

echo '* CREATE SUFFICIENT ENTROPY'
create_sufficient_entropy

echo '* READ CONFIGURATION OPTIONS'
source configuration.options

echo '* CREATE WLST PROPERTIES FILE'
cat > ${CONFIG_BASE}/${DOMAIN_NAME}.properties <<EOF
mw_home=${MW_HOME}
wl_home=${WL_HOME}
soa_home=${SOA_HOME}
fmw_home=${FMW_HOME}

domain_home=${DOMAIN_HOME}
nm_home=${NM_HOME}
domain_app_home=${DOMAIN_APP_HOME}
java_home=${JAVA_HOME}

node_manager_username=${NM_USERNAME}
node_manager_password=${NM_PASSWORD}
node_manager_listen_address=${INSTALL_HOST}
node_manager_listen_port=${NM_PORT}
node_manager_mode=plain

admin_server_name=AdminServer
admin_username=${AS_USERNAME}
admin_password=${AS_PASSWORD}
admin_server_listen_port=${AS_PORT}
admin_server_listen_address=${INSTALL_HOST}

domain_name=${DOMAIN_NAME}

machine_listen_address=${INSTALL_HOST}
machine_uid=oracle
machine_grp=g_fmw

# https://docs.oracle.com/middleware/1213/soasuite/SOEDG/edg_extdomain_bam.htm#SOEDG169
# https://docs.oracle.com/middleware/1213/wls/WLDTR/fmw_templates.htm#WLDTR508
# OSB-MGD-SVRS-COMBINED, creates an OSB Managed Server which includes Oracle WSM Policy Manager.
# OSB-MGD-SVRS-ONLY, creates an OSB Managed Server which does not include Oracle WSM Policy Manager.
# SOA-MGD-SVRS—Creates a SOA Managed Server which includes Oracle WSM Policy Manager.
# SOA-MGD-SVRS-ONLY Creates a SOA Managed Server which does not include Oracle WSM Policy Manager.
# BAM12-MGD-SVRS Creates a BAM Managed Server which includes Oracle WSM Policy Manager.
# BAM12-MGD-SVRS-ONLY Creates a BAM Managed Server which does not include Oracle WSM Policy Manager.
soa_server_groups_list=SOA-MGD-SVRS
osb_server_groups_list=OSB-MGD-SVRS-COMBINED
bam_server_groups_list=BAM12-MGD-SVRS

data_source_url=jdbc:oracle:thin:@//${INSTALL_HOST}:1521/${DB_SERVICE}
data_source_driver=oracle.jdbc.OracleDriver
data_source_user_prefix=DEV
data_source_password=${DB_DS_PASSWORD}
data_source_test=SQL SELECT 1 FROM DUAL
EOF


echo '* CREATE AND CONFIGURE DOMAIN'
create_domain

echo '* CHANGE DOMAIN ENVIRONMENT CONFIGURATION'
change_domainenv_settings

echo "* CREATING DESKTOP LINKS AND CONTROL SCRIPTS"

echo "  - CREATE SCRIPT AND TMP DIRECTORIES"
export user_homedir=$(echo ~)
if [ ! -d ${user_homedir}/Oracle ] ; then
  mkdir -p ${user_homedir}/Oracle
fi

if [ ! -d ${CONFIG_BASE}/TMP ] ; then
  mkdir ${CONFIG_BASE}/TMP
fi

create_nodemanager_control_menu_item

create_adminserver_control_menu_item

create_server_control_menu_item "soa_server1"  
create_server_control_menu_item "osb_server1"
create_server_control_menu_item "bam_server1"

echo "  - CREATE NEW MENU CATEGORY, FUSIONMIDDLEWARE"

## Create new menu associated to specific categories
sudo bash -c 'cat > /etc/xdg/menus/applications-merged/FusionMiddleware.menu <<EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>Fusion Middleware</Name>
    <Directory>FMW.directory</Directory>
    <Include>
        <Category>FusionMiddleware</Category>
    </Include>
  </Menu>
</Menu>
EOF'

echo "  - CREATE NEW DESKTOP DIRECTORIES TYPE, FMW"
## Create new directory Type
sudo bash -c 'cat > /usr/share/desktop-directories/FMW.directory <<EOF
[Desktop Entry]
Type=Directory
Encoding=UTF-8
Name=Fusion Middleware
EOF'

echo "  - CREATE WLST SERVER CONTROL SCRIPT"
cat > ${user_homedir}/Oracle/server_control_${DOMAIN_NAME}.py <<EOFWLS
# wlst

import sys

if len(sys.argv) != 3 :
    print "Supply [stop|start] and managed server name"
    exit()

nmConnect(node_manager_username,node_manager_password,node_manager_listen_address,node_manager_listen_port,'${DOMAIN_NAME}','${DOMAIN_HOME}',node_manager_mode)

if sys.argv[1] == "stop" :
    try:
        if nmServerStatus(sys.argv[2]) == "RUNNING" :
            print "Stopping Managed Server " + sys.argv[2]
            nmKill(sys.argv[2])
        else :
            print "Managed Server already STOPPED"
            print "So it is stopped successfully"
    except:
        print "Failed Stopping Managed Server"
        exit()

if sys.argv[1] == "start" :
    try:
        if nmServerStatus(sys.argv[2]) != "RUNNING" :
            print "Starting Managed Server " + sys.argv[2]
            nmStart(sys.argv[2])
        else :
            print "Managed Server already RUNNING"
            print "So it is started successfully"

    except:
        print "Failed Starting Managed Server"
        exit()

EOFWLS


