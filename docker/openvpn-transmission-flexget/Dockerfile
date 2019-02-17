FROM alpine:3.8
#FROM lsiobase/alpine.python:3.7

# Set python to use utf-8 rather than ascii.
ENV PYTHONIOENCODING="UTF-8"
ENV DOCKERIZE_VERSION=v0.6.0
# set version for s6 overlay
ARG OVERLAY_VERSION="v1.21.8.0"
ARG OVERLAY_ARCH="amd64"

# Add edge/testing repositories.
RUN printf "\
@edge http://nl.alpinelinux.org/alpine/edge/main\n\
@testing http://nl.alpinelinux.org/alpine/edge/testing\n\
@community http://nl.alpinelinux.org/alpine/edge/community\n\
" >> /etc/apk/repositories

RUN \
echo "**** install build packages ****" \
    && apk update \
    && apk add --no-cache \
#        --virtual=build-dependencies \
    	tar apk-tools bash dumb-init ip6tables ufw@testing openvpn shadow transmission-daemon curl jq ssmtp rsync nano \
        py2-pip \
&& echo "Install dockerize $DOCKERIZE_VERSION" \
    && wget -qO- https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz | tar xz -C /usr/bin \
&& echo "**** add s6 overlay ****" \
    && curl -o /tmp/s6-overlay.tar.gz -L \
	    "https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.gz" \
    && tar xfz /tmp/s6-overlay.tar.gz -C /

RUN pip install -U pip \
    # Make sure to install setuptools version >=36 to avoid a race condition, see:
    # https://github.com/pypa/setuptools/issues/951
    && pip install -U setuptools>=36 \
    && pip install -U urllib3[socks] \
    && pip install -U subliminal \
    && pip install -U chardet \
    && pip install -U irc_bot \
    && pip install -U rarfile \
    && pip install -U transmissionrpc \
    # Install flexget last (it might force specific versions of other packages).
    && pip install -U flexget

RUN \
echo "**** clean up ****" \
    && rm -rf /root/.cache /tmp/*

VOLUME /data
VOLUME /config

ENV PUID=1000

RUN \
echo "**** Creating user to run transmission *****" \
    && addgroup -g ${PUID} abc \
    && adduser -D -H -s /bin/bash -u ${PUID} -G abc abc \
    && passwd -d abc \
    && addgroup abc wheel

# Copy local files.
COPY ./bashrc /root/.bashrc
COPY ./bash_history* /root/.bash_history
COPY etc/ /etc
RUN chmod -v +x /etc/cont-init.d/*

# Expose port and run
# Web UI and rpc port
EXPOSE 9091
CMD ["dumb-init", "/etc/openvpn/start.sh"]
