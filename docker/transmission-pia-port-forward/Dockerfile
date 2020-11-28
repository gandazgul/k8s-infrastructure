FROM alpine:3.11

RUN apk add --no-cache bash curl nano

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

RUN touch /var/log/crond.log

# start crond to run the transmission port cronjob
CMD ["crond", "-f", "-L", "/var/log/crond.log"]
