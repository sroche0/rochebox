#!/bin/bash

# Remove symlink to ${HOME}/.local/bin/crabbot
if [ -L "${HOME}/.local/bin/crabbot" ]; then
    rm "${HOME}/.local/bin/crabbot"
fi

# Remove symlink to ${HOME}/.crabbot
if [ -L "${HOME}/.crabbot" ]; then
    rm "${HOME}/.crabbot"
fi

# Remove data directory ${APPDATA}
#if [ -d "${APPDATA}" ]; then
#    echo "Removing data directory ${APPDATA}"
#    rm -rf "$APPDATA"
#fi

echo "Uninstallation completed successfully."