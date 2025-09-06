# CrabBot

CrabBot is a simple command-line tool that automates common tasks related to managing Docker containers for game servers. It allows users to easily perform actions such as starting, stopping, updating, pulling images, checking status, or restarting their containerized dedicated game server instances.

- **Server**:  These names correspond to directories containing specific configurations for different game servers.

- **Action**: This specifies what operation should be carried out on the chosen server instance. Possible actions include:
  - `up`: Starts the server container(s).
  - `down`: Stops the server container(s) gracefully.
  - `pull`: Pulls updated images for sever container(s) without restarting them.
  - `update`: Combines pulling new images with stopping and starting containers to ensure any pre-up or pre-down actions are run
  - `ps`: Checks status of all associated Docker Compose-managed containers for a given server instance.
  - `restart`: Runs docker restart on a container. *WARNING:* Skips any pre up or pre-down actions.


```
crabbot <server_name> [up|down|pull|update|ps|restart]
```
### Installation

The install script will create a symlink of the crabbot script `~/.local/bin/crabbot`. It will also create a symlink of 
the current directory with the compose yml files and config folders to `~/.crabbot`. After running installation script 
you can edit the values in .env or any of the override.env files as you see fit or leave them at defaults. 
PUID and PGID will default to the uid and gid of the user that runs the install script. The default `APPDATA` directory 
where persistent server data such as game binaries and save files will be kept is `~/Games/crabbot`

```bash
./bin/install.sh
```

### Usage Examples:
#### Start a Server Container (up)
```
$ crabbot <server_name> up
Example: $ crabbot project_zomboid up
```

#### Stop a Running Server Container (down)
```
$ crabbot <server_name> down
Example: $ crabbot project_zomboid down
```
#### Pull Latest Image Version (pull)
```
$ crabbot <server_name> pull
Example: $ crabbot project_zomboid pull
```
#### Update and restart server (update)
```
$ crabbot <server_name> update
Example: $ crabbot project_zomboid update
```
#### Check Status of a server container (ps):
```
$ crabbot <server_name> ps
Example: $ crabbot project_zomboid ps
```
#### Restart server (restart)
```
$ crabbot <server_name> restart
Example: $ crabbot project_zomboid restart
```

### Uninstallation
The uninstall script will remove the symlinks created by the install script but leave any persistent data in the 
configured `APPDATA` as well as leave any local changes made to env files

```bash
./bin/uninstall.sh
```
