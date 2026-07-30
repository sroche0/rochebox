FROM cm2network/steamcmd:root

LABEL maintainer="shawn@rochebox.net"

ARG USER
ARG SERVER_BRANCH

# STEAMAPP/STEAMAPPDIR must be their own ENV instructions, set before anything that
# references them: within a single multi-line ENV instruction, later keys can't see
# earlier keys set in that same instruction -- only vars from previous instructions.
# Getting this wrong silently resolves STEAMAPPDIR to just "${HOMEDIR}/" (STEAMAPP
# empty), which is exactly what happened here before this fix.
ENV STEAMAPP=projectzomboid
ENV STEAMAPPDIR="${HOMEDIR}/${STEAMAPP}"

ENV STEAMAPPID=380870 \
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
    SERVER_BRANCH=${SERVER_BRANCH} \
    MAX_RAM=8192m

COPY entry.sh "${HOMEDIR}/entry.sh"
COPY install.scmd "${HOMEDIR}/install.scmd"

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