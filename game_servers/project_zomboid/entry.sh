#! /bin/bash
echo running "${HOME}/steamcmd/steamcmd.sh +force_install_dir ${HOME}/projectzomboid +login anonymous +app_update ${STEAMAPPID} -beta ${SERVER_BRANCH} validate +quit"
${HOME}/steamcmd/steamcmd.sh +force_install_dir ${HOME}/projectzomboid +login anonymous +app_update ${STEAMAPPID} -beta ${SERVER_BRANCH} validate +quit
/bin/bash ${HOME}/projectzomboid/start-server.sh -servername $SERVER_NAME -adminusername $ADMIN_USERNAME -adminpassword $ADMIN_PASSWORD

# tail -f /dev/null