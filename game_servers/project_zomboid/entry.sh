#! /bin/bash
set -euo pipefail

beta_args=""
if [ -n "${SERVER_BRANCH}" ]; then
    beta_args="-beta ${SERVER_BRANCH} "
fi

# install.scmd is a steamcmd script, not a shell script -- steamcmd doesn't expand
# ${VAR} itself, so render its __PLACEHOLDER__ tokens here before running it. This
# also means the file is safe to bind-mount over for edits without rebuilding the
# image (see compose.project_zomboid.yml).
install_script="${HOME}/install.rendered.scmd"
sed \
    -e "s|__STEAMAPPDIR__|${STEAMAPPDIR}|g" \
    -e "s|__STEAMAPPID__|${STEAMAPPID}|g" \
    -e "s|__BETA_ARGS__|${beta_args}|g" \
    "${HOME}/install.scmd" > "${install_script}"

if grep -qE '__[A-Z_]+__' "${install_script}"; then
    echo "ERROR: unresolved placeholder(s) left in ${install_script} -- did install.scmd" >&2
    echo "get edited (e.g. via the optional bind mount) without updating entry.sh's sed step?" >&2
    grep -nE '__[A-Z_]+__' "${install_script}" >&2
    exit 1
fi

echo "Running steamcmd with rendered install script:"
cat "${install_script}"
"${HOME}/steamcmd/steamcmd.sh" +runscript "${install_script}"

# Zomboid only reads -Xmx from this file, not from an env var -- steamcmd's
# validate step above resets it to Indie Stone's shipped default every run.
sed -i "s/\"-Xmx[^\"]*\"/\"-Xmx${MAX_RAM}\"/" "${HOME}/projectzomboid/ProjectZomboid64.json"

exec /bin/bash "${HOME}/projectzomboid/start-server.sh" -servername "$SERVER_NAME" -adminusername "$ADMIN_USERNAME" -adminpassword "$ADMIN_PASSWORD"
