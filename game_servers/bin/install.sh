#!/bin/bash

get_local_timezone() {
    local timezone
    timezone="America/New_York"

    if command -v timedatectl &> /dev/null; then
        timezone=$(timedatectl status | grep 'Time zone' | awk '{print $3}')
    else
        if [ -f "/etc/timezone" ]; then
            timezone=$(cat /etc/timezone)
        fi
    fi
    echo "$timezone"
}

copy_sample_env_files() {
    # walk through each directories and copy sample.override.env files to override.env if they dont exist already.
    # do the same for .env and set default values for the current user
    local user_id
    local user_group
    local timezone
    local env_file
    local sample_override_file
    local override_file

    user_id="$(id -u)"
    user_group="$(id -g)"
    timezone=$(get_local_timezone)
    env_file="$(pwd)/.env"

    echo "Staging env files..."
    if [ ! -f "${env_file}" ]; then
        echo "Using current user info for .env"
        echo "    PUID=${user_id}"
        echo "    PGID=${user_group}"
        echo "    TZ=${timezone}"

        cp "$(pwd)/sample.env" "${env_file}"
        sed -i "s/PUID=.*/PUID=${user_id}/g" "${env_file}"
        sed -i "s/PGID=.*/PGID=${user_group}/g" "${env_file}"
        sed -i "s|TZ=.*|TZ='${timezone}'|g" "${env_file}"
    fi

    while IFS= read -r -d '' dir; do
        sample_override_file="$dir/sample.override.env"
        override_file="$dir/override.env"

        if [ -f "$sample_override_file" ] && [ ! -f "$override_file" ]; then
            cp "$sample_override_file" "$override_file"
        fi
    done < <(find . -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0)
}

add_to_path() {
    local profile=$1
    local bin_path=$2
    local path_string="export PATH=\"${bin_path}:\$PATH\""
    echo '# Added by CrabBot' >> "$profile"
    echo $path_string >> "$profile"
}

create_symlinks() {
    echo "Creating symlinks..."
    local local_bin_path="${HOME}/.local/bin"
    mkdir -p "$local_bin_path"

    # Add ~/.local/bin to PATH if it's not already there
    if [[ ":$PATH:" != *":${local_bin_path}:"* ]]; then
        if [[ "$SHELL" == *"/bash" ]]; then
            add_to_path "${HOME}/.bash_profile" ${local_bin_path}
            source "${HOME}/.bash_profile"
        elif [[ "$SHELL" == *"/zsh" ]]; then
            add_to_path "${HOME}/.zshrc" ${local_bin_path}
            source "${HOME}/.zshrc"
        else
            echo "Unknown shell: $SHELL"
            echo "Please add ${local_bin_path} to your \$PATH manually:"
            echo '  export PATH="$HOME/.local/bin:$PATH"'
        fi
    fi

    if [ ! -f "$local_bin_path/crabbot" ]; then
      ln -s "$(pwd)/crabbot" "$local_bin_path/crabbot"
    fi
}

copy_sample_env_files
source .env
mkdir -p "$APPDATA"
create_symlinks

echo "Installation completed successfully."
