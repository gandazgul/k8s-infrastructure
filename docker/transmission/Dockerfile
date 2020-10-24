FROM alpine:3.11

ENV UID=1000 \
    GID=1000 \
    RPC_PORT=9091

VOLUME /data

EXPOSE $RPC_PORT

RUN \
echo "**** Creating user to run transmission *****" \
    && addgroup -g ${GID} abc \
    && adduser -D -H -s /bin/bash -u ${UID} -G abc abc \
    && passwd -d abc \
    && addgroup abc wheel \
    && apk add --no-cache bash curl nano transmission-daemon

# transmission complains about these on startup
RUN \
  echo "**** Configuring system values for transmission *****" \
  && echo "net.core.rmem_max = 4194304" >> /etc/sysctl.conf \
  && echo "net.core.wmem_max = 1048576" >> /etc/sysctl.conf

# Configure the port-forward script
RUN \
    echo "**** Adding cronjob to keep the transmission port open *****" \
    # at reboot wait 60s for VPN to initialize then set the port
    && echo '@reboot sleep 60s && /usr/bin/port-forwarding.sh | while IFS= read -r line; do echo "$(date) $line"; done >> /var/log/pia_portforward.log 2>&1 #PIA Port Forward' >> /etc/crontabs/root \
    # refresh port every 2 hours
    && echo '0 */2 * * * /usr/bin/port-forwarding.sh | while IFS= read -r line; do echo "$(date) $line"; done >> /var/log/pia_portforward.log 2>&1 #PIA Port Forward' >> /etc/crontabs/root

COPY ./port-forwarding.sh /usr/bin/port-forwarding.sh
RUN chmod +x /usr/bin/port-forwarding.sh
RUN touch /var/log/pia_portforward.log

COPY ./entrypoint.sh /usr/bin/entrypoint.sh
RUN chmod +x /usr/bin/entrypoint.sh

CMD /usr/bin/entrypoint.sh
