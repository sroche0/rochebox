#! /bin/bash
set -euo pipefail

beta_args=()
if [ -n "${SERVER_BRANCH}" ]; then
    beta_args=(-beta "${SERVER_BRANCH}")
fi

echo "Running steamcmd: app_update ${STEAMAPPID} ${beta_args[*]:-} validate"
"${HOME}/steamcmd/steamcmd.sh" +force_install_dir "${HOME}/projectzomboid" +login anonymous +app_update "${STEAMAPPID}" "${beta_args[@]}" validate +quit

# Zomboid only reads -Xmx from this file, not from an env var -- steamcmd's
# validate step above resets it to Indie Stone's shipped default every run.
sed -i "s/\"-Xmx[^\"]*\"/\"-Xmx${MAX_RAM}\"/" "${HOME}/projectzomboid/ProjectZomboid64.json"

exec /bin/bash "${HOME}/projectzomboid/start-server.sh" -servername "$SERVER_NAME" -adminusername "$ADMIN_USERNAME" -adminpassword "$ADMIN_PASSWORD"
