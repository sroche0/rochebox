FROM cm2network/steamcmd:root

LABEL maintainer="shawn@rochebox.net"

ARG USER
ARG SERVER_BRANCH

ENV STEAMAPPID=380870 \
    STEAMAPP=projectzomboid \
    STEAMAPPDIR="${HOMEDIR}/${STEAMAPP}" \
    HOME=/home/steam \
    CONFIG_DIR=${STEAMAPPDIR}/config \
    ADMIN_USERNAME=admin \
    ADMIN_PASSWORD=admin \
    DEFAULT_PORT=16261 \
    UDP_PORT=16262 \
    RCON_PORT=27015 \
    SERVER_NAME=pzserver \
    STEAM_VAC=true \
    USE_STEAM=true \
    GENERATE_SETTINGS=true \
    SERVER_BRANCH="" \
    MEMORY_XMX_GB=8 \
    MEMORY_XMS_GB="" \
    SERVER_BRANCH=""

COPY scripts/entry.sh "${HOMEDIR}/entry.sh"
COPY scripts/install.scmd "${HOMEDIR}/install.scmd"

RUN set -x \
	# Install, update & upgrade packages
	# && apt-get update \
	# && apt-get install -y --no-install-recommends --no-install-suggests \
	# 	envsubst \
	&& mkdir -p "${STEAMAPPDIR}" \
	&& chmod +x "${HOMEDIR}/entry.sh" \
	&& chown -R "${USER}:${USER}" "${HOMEDIR}/entry.sh" "${STEAMAPPDIR}" "${HOMEDIR}/install.scmd" \
	# Clean up
	&& rm -rf /var/lib/apt/lists/* 



# Switch to user
USER ${USER}

WORKDIR ${HOMEDIR}

ENTRYPOINT ["bash", "entry.sh"]

# Expose ports
EXPOSE 27015/tcp \
	27015/udp \
	27020/udp \
    16261/tcp \
    16262/udp

HEALTHCHECK --start-period=5m \
            CMD pgrep "ProjectZomboid" > /dev/null || exit 1