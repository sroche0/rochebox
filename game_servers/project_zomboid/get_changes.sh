#!/bin/bash
cwd=$(pwd)
cd /home/shawn/git/game_configs
echo 'Pulling changes from git...'
git pull
python3 project_zomboid/mod_manager.py -gen
echo 'Restarting zomboid container...'
docker stop zomboid
docker-compose up -d
cd $cwd
