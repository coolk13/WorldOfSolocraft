#!/bin/bash

# This script **is not** idempotent: it's a one-time thing.
# If you do run it several times, then things should be OK,
# but there's not guarantee.

export WHERE_WAS_I=$(pwd)

source config.production.sh

echo ""
echo "#########################################################"
echo "# Base OS"
echo "#########################################################"
echo ""

# Install the required packages (requires root)
# (This is the MariaDB set of packages)
# This disables dumb TUI popups, preventing automated installs
export DEBIAN_FRONTEND=noninteractive
sudo apt update
sudo apt install -y git cmake make gcc g++ clang libssl-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev mariadb-server mariadb-client libmariadb-dev libmariadb-dev-compat unzip ufw python3-venv net-tools

# Install extra nice to have
sudo apt install -y fail2ban lsof

# A bit of clean up
sudo apt autoremove

# Prepare firewall for remote access
# You can disable these lines if you don't want a firewall in place
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 0.0.0.0/0 to any port 22 # SSH - restrict the crap out this!!
sudo ufw allow from 0.0.0.0/0 to any port $AZEROTHCORE_SERVER_BIND_PORT # world server
sudo ufw allow from 0.0.0.0/0 to any port 3724 # auth server
sudo ufw allow from 0.0.0.0/0 to any port 3306 # MariaDB server
sudo ufw --force enable

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

# Obviously need to make sure the server is active
sudo systemctl restart mariadb

if [ ! -f "./database.create.lock" ];
then
  echo "Creating the databases..."
  sudo mysql < "${HOME}/${AZEROTHCORE_SOURCE_DIR}/data/sql/create/create_mysql.sql"
  touch ./database.create.lock
else
  echo "Database already created, skiping..."
fi

if [ ! -f "./database.${AZEROTHCORE_AUTH_DATABASE}.lock" ];
then
  touch "./database.${AZEROTHCORE_AUTH_DATABASE}.lock"
  echo "Creating the auth tables..."
  cd "${HOME}/${AZEROTHCORE_SOURCE_DIR}/data/sql/base/db_auth/"
  for sqlfile in $(ls *.sql); do sudo mysql $AZEROTHCORE_AUTH_DATABASE < $sqlfile; done
else
  echo "Auth tables already created, skipping..."
fi

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

# Prevent the need to type the password all the time
cat <<EOF > $HOME/.my.cnf 
[client]
password=acore
EOF

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
  cp confs/worldserver.main.conf "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
fi

# We now _always_ do this
echo "BindIP = $AZEROTHCORE_SERVER_BIND_IP" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
echo "WorldServerPort = $AZEROTHCORE_SERVER_BIND_PORT" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
echo "WorldDatabaseInfo = \"${AZEROTHCORE_SERVER_BIND_IP};3306;acore;acore;$AZEROTHCORE_WORLD_DATABASE\"" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
echo "LoginDatabaseInfo = \"${AZEROTHCORE_SERVER_BIND_IP};3306;acore;acore;$AZEROTHCORE_AUTH_DATABASE\"" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"
echo "CharacterDatabaseInfo = \"${AZEROTHCORE_SERVER_BIND_IP};3306;acore;acore;$AZEROTHCORE_CHARACTERS_DATABASE\"" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/worldserver.conf"

if [ ! -f "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/authserver.conf" ];
then
  cp confs/authserver.conf "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/"
fi

echo "BindIP = $AZEROTHCORE_SERVER_BIND_IP" >> "${HOME}/${AZEROTHCORE_SERVER_DIR}/etc/authserver.conf"

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
sudo systemctl stop azerothcore-world-server.service

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
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET name = '${AZEROTHCORE_SERVER_REALM_NAME}' WHERE id = 1;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET address = '${AZEROTHCORE_SERVER_REMOTE_ENDPOINT}' WHERE id = 1;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET localAddress = '${AZEROTHCORE_SERVER_BIND_IP}' WHERE id = 1;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET localSubnetMask = '${AZEROTHCORE_SERVER_LOCAL_SUBNETMASK}' WHERE id = 1;"
mysql -u acore $AZEROTHCORE_AUTH_DATABASE -e "UPDATE realmlist SET port = '${AZEROTHCORE_SERVER_BIND_PORT}' WHERE id = 1;"

# Configure our world content
source import_sql.sh

# Create systemd .service files
cat <<EOF > azerothcore-world-server.service
[Unit]
Description=AzerothCore 3.3.5a World Server
After=network.target

[Service]
User=superman
Group=superman
PrivateTmp=true
Type=simple
PIDFile=/run/azerothcore/worldserver.pid
WorkingDirectory=${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/
ExecStart=${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/worldserver

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > azerothcore-auth-server.service
[Unit]
Description=AzerothCore 3.3.5a Auth Server
After=network.target

[Service]
User=superman
Group=superman
PrivateTmp=true
Type=simple
PIDFile=/run/azerothcore/authserver.pid
WorkingDirectory=${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/
ExecStart=${HOME}/${AZEROTHCORE_SERVER_DIR}/bin/authserver

[Install]
WantedBy=multi-user.target
EOF

# This ensures the admin group, of which the user installing WoS should be a member,
# can manage the auth and world server systemd services without a password. This is
# required for the scheduled living-world scripts.
sudo cat <<EOF > /etc/sudoers.d/999-wos 
%admin ALL = (root) NOPASSWD: /usr/bin/systemctl start azerothcore-world-server.service
%admin ALL = (root) NOPASSWD: /usr/bin/systemctl start azerothcore-auth-server.service
%admin ALL = (root) NOPASSWD: /usr/bin/systemctl stop azerothcore-world-server.service
%admin ALL = (root) NOPASSWD: /usr/bin/systemctl stop azerothcore-auth-server.service
EOF

# Move the service files into place
sudo mv azerothcore-world-server.service /etc/systemd/system/azerothcore-world-server.service
sudo mv azerothcore-auth-server.service /etc/systemd/system/azerothcore-auth-server.service

# Enable and start our services
sudo systemctl enable azerothcore-auth-server.service
sudo systemctl start azerothcore-auth-server.service

sudo systemctl enable azerothcore-world-server.service
sudo systemctl start azerothcore-world-server.service
