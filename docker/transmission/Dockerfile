FROM alpine:3.11

ENV UID=1000 \
    GID=1000 \
    RPC_PORT=9091 \
    PEER_PORT=29091

RUN \
echo "**** Creating user to run transmission *****" \
    && addgroup -g ${GID} abc \
    && adduser -D -H -s /bin/bash -u ${UID} -G abc abc \
    && passwd -d abc \
    && addgroup abc wheel \
    && apk add --no-cache bash curl nano transmission-daemon

# Copy local files.
#COPY ./bashrc /root/.bashrc
#COPY ./bash_history* /root/.bash_history

VOLUME /data

EXPOSE $RPC_PORT $PEER_PORT $PEER_PORT/UDP

CMD su -s /bin/bash abc -c \
        "/usr/bin/transmission-daemon --foreground -g /data --port ${RPC_PORT} --peerport ${PEER_PORT}"

#openvpn --up-delay --up /etc/openvpn/tunnelUp.sh --down /etc/openvpn/tunnelDown.sh