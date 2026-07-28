#!/bin/bash
set -euo pipefail

cwd=$(pwd)
repo_root=$(git rev-parse --show-toplevel)

echo 'Pulling changes from git...'
git -C "$repo_root" pull

cd "$repo_root/game_servers"
python3 project_zomboid/scripts/mod_manager.py -gen

echo 'Updating zomboid container...'
crabbot project_zomboid update

cd "$cwd"
