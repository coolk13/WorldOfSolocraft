#!/bin/bash

# You'll likely want to edit these if you want to allow
# remote connections to your server
export AZEROTHCORE_SERVER_REMOTE_ENDPOINT=127.0.0.1
export AZEROTHCORE_SERVER_BIND_IP=127.0.0.1

# You can probably ignore these flags
export AZEROTHCORE_SOURCE_DIR=azerothcore
export AZEROTHCORE_SOURCE_BRANCH=master
export AZEROTHCORE_SERVER_DIR=azerothcore-server
export AZEROTHCORE_SERVER_BACKUPS_DIR=azerothcore-server-backups
export AZEROTHCORE_SERVER_REALM_NAME=AzerothCore
export AZEROTHCORE_SERVER_BIND_PORT=8085
export AZEROTHCORE_SERVER_LOCAL_SUBNETMASK=255.255.255.0
export AZEROTHCORE_AUTH_DATABASE="acore_auth"
export AZEROTHCORE_WORLD_DATABASE="acore_world"
export AZEROTHCORE_CHARACTERS_DATABASE="acore_characters"
