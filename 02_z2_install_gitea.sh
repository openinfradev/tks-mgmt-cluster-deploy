#!/bin/sh
set -e

source lib/common.sh

GROUP=$(groups $USER | awk '{print $1}')

sudo apt install -y sqlite

sudo mkdir -p /var/lib/gitea/{custom,data,log}
sudo chown -R $USER:$GROUP /var/lib/gitea/
sudo chmod -R 750 /var/lib/gitea/
sudo mkdir -p /etc/gitea
sudo chown root:$GROUP /etc/gitea
sudo chmod 770 /etc/gitea
cp -f templates/app.ini.gitea.example /etc/gitea/app.ini

export GITEA_WORK_DIR=/var/lib/gitea/
nohup $ASSET_DIR/gitea web -c /etc/gitea/app.ini 2>&1 1>gitea.log &
