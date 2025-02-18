#!/bin/bash

# This script **is not** idempotent: it's a one-time thing.
# If you do run it several times, then things should be OK,
# but there's not guarantee.

export WHERE_WAS_I=$(pwd)

source config.ptr.sh

echo ""
echo "#########################################################"
echo "# Base OS"
echo "#########################################################"
echo ""

sudo ufw allow from 0.0.0.0/0 to any port $AZEROTHCORE_SERVER_BIND_PORT # world server

echo ""
echo "#########################################################"
echo "# AzerothCore "
echo "#########################################################"
echo ""

# Clone AzerothCore
if [ -d "${HOME}/${AZEROTHCORE_SOURCE_DIR}" ];
then
  cd "${HOME}/${AZEROTHCORE_SOURCE_DIR}"
  git pull
  cd $WHERE_WAS_I
else
  git clone https://github.com/azerothcore/azerothcore-wotlk.git --branch $AZEROTHCORE_SOURCE_BRANCH --single-branch --depth 1 "${HOME}/${AZEROTHCORE_SOURCE_DIR}"
fi

echo ""
echo "#########################################################"
echo "# Initialise Database"
echo "#########################################################"
echo ""

# Prepare MariaDB server for AzerothCore (need to be root)
# NOTE: you should probably lock down MySQL, especially the root user
# sudo mysql < sql/m-00-initial-database-setup.main.sql

if [ ! -f "./database.${AZEROTHCORE_CHARACTERS_DATABASE}.lock" ];
then
  touch "./database.${AZEROTHCORE_CHARACTERS_DATABASE}.lock"
  echo "Creating the character tables..."
  cd "${HOME}/${AZEROTHCORE_SOURCE_DIR}/data/sql/base/db_characters/"
  for sqlfile in $(ls *.sql); do sudo mysql $AZEROTHCORE_CHARACTERS_DATABASE < $sqlfile; done
else
  echo "Character tables already created, skipping..."
fi

if [ ! -f "./database.${AZEROTHCORE_WORLD_DATABASE}.lock" ];
then
  touch "./database.${AZEROTHCORE_WORLD_DATABASE}.lock"
  echo "Creating the world tables..."
  cd "${HOME}/${AZEROTHCORE_SOURCE_DIR}/data/sql/base/db_world/"
  for sqlfile in $(ls *.sql); do sudo mysql $AZEROTHCORE_WORLD_DATABASE < $sqlfile; done
else
  echo "World tables already created, skipping..."
fi

cd $WHERE_WAS_I

echo ""
echo "#########################################################"
echo "# AzerothCore - Modules"
echo "#########################################################"
echo ""

source setup.modules.sh

echo ""
echo "#########################################################"
echo "# AzerothCore - compile all"
echo "#########################################################"
echo ""

# Include our compile script (including modules)
source compile.sh

# Return HOME
cd $WHERE_WAS_I

# Setup directory for world/client data files
mkdir -p "${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/data"

# We download the v16 maps, mmaps, VMOs, cameras, etc.
if [ ! -f "${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/data/v16.zip" ];
then
  wget https://github.com/wowgaming/client-data/releases/download/v16/data.zip
  mv data.zip "${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/data/v16.zip"
  # Extract them to the server's data directory
  unzip "${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/data/v16.zip" -d "${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/data"
fi

echo ""
echo "#########################################################"
echo "# Server Configuration Files"
echo "#########################################################"
echo ""

# Move our configurations in place
# ... but only if they don't already exist, because there might be
# custom changes we'll end up overriding...
if [ ! -f "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf" ];
then
  cp confs/worldserver.ptr.conf "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
  echo "BindIP = $AZEROTHCORE_SERVER_BIND_IP" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
  echo "WorldServerPort = $AZEROTHCORE_SERVER_BIND_PORT" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
   echo "WorldDatabaseInfo = \"${AZEROTHCORE_SERVER_BIND_IP};3306;acore;acore;$AZEROTHCORE_WORLD_DATABASE\"" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
  echo "LoginDatabaseInfo = \"${AZEROTHCORE_SERVER_BIND_IP};3306;acore;acore;$AZEROTHCORE_AUTH_DATABASE\"" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
  echo "CharacterDatabaseInfo = \"${AZEROTHCORE_SERVER_BIND_IP};3306;acore;acore;$AZEROTHCORE_CHARACTERS_DATABASE\"" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
fi

echo ""
echo "#########################################################"
echo "# First run of World Server"
echo "#########################################################"
echo ""

mkdir -p "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/modules/"
cp confs/modules/*.conf.dist "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/modules/"

# Now we need to run the worldserver so that the database is populated
echo ""
echo "===================================================================================="
echo ""
echo "World Server is about to be run to initialize DB and accounts."
echo "When its finished running, and you see the AC> prompt, create whatever accounts"
echo "you need NOW, then Contrl+C so the script can finalise the setup preocess."
echo ""
echo "See here for creating account: https://www.azerothcore.org/wiki/creating-accounts"
echo ""
echo "===================================================================================="
echo ""

# Shutdown an existing server, if applicable
sudo systemctl stop azerothcore-ptr-world-server.service

# Make the Console is enabled first
sed -i 's/Console.Enable = 0/Console.Enable = 1/g' "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
read -p "Press any key to run worldserver..."

cd "${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/"
./worldserver

# I disable the console at this point because I'm running the service using systemd.
sed -i 's/Console.Enable = 1/Console.Enable = 0/g' "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
cd $WHERE_WAS_I

# Additional SQL steps
# Configure our realm related information
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET name = '${AZEROTHCORE_SERVER_REALM_NAME}' WHERE id = 2;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET address = '${AZEROTHCORE_SERVER_REMOTE_ENDPOINT}' WHERE id = 2;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET localAddress = '${AZEROTHCORE_SERVER_BIND_IP}' WHERE id = 2;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET localSubnetMask = '${AZEROTHCORE_SERVER_LOCAL_SUBNETMASK}' WHERE id = 2;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET port = '${AZEROTHCORE_SERVER_BIND_PORT}' WHERE id = 2;"

# Configure our world content
source import_sql.sh

# Create systemd .service files
cat <<EOF > azerothcore-ptr-world-server.service
[Unit]
Description=AzerothCore 3.3.5a World Server
After=network.target

[Service]
PrivateTmp=true
Type=simple
PIDFile=/run/azerothcore/worldserver.pid
WorkingDirectory=${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/
ExecStart=${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/worldserver

[Install]
WantedBy=multi-user.target
EOF

# This ensures the admin group, of which the user installing WoS should be a member,
# can manage the auth and world server systemd services without a password. This is
# required for the scheduled living-world scripts.
sudo cat <<EOF > /etc/sudoers.d/999-wos-ptr 
%admin ALL = (root) NOPASSWD: /usr/bin/systemctl start azerothcore-ptr-world-server.service
%admin ALL = (root) NOPASSWD: /usr/bin/systemctl stop azerothcore-ptr-world-server.service
EOF

# Move the service files into place
sudo mv azerothcore-ptr-world-server.service /etc/systemd/system/azerothcore-ptr-world-server.service

# Enable and start our service
sudo systemctl enable azerothcore-ptr-world-server.service
sudo systemctl start azerothcore-ptr-world-server.service
