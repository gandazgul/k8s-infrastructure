FROM alpine:3.11

ENV UID=1000 \
    GID=1000 \
    RPC_PORT=9091

RUN \
echo "**** Creating user to run transmission *****" \
    && addgroup -g ${GID} abc \
    && adduser -D -H -s /bin/bash -u ${UID} -G abc abc \
    && passwd -d abc \
    && addgroup abc wheel \
    && apk add --no-cache bash curl nano transmission-daemon

VOLUME /data

EXPOSE $RPC_PORT

CMD su -s /bin/bash abc -c \
        "/usr/bin/transmission-daemon --foreground -g /data --port ${RPC_PORT}"
