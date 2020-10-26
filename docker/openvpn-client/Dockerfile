FROM dperson/openvpn-client

RUN \
    echo "**** Adding cronjob to keep the transmission port open *****" \
    && echo '@reboot sleep 60s && /usr/bin/port-forwarding.sh | while IFS= read -r line; do echo "$(date) $line"; done >> /var/log/pia_portforward.log 2>&1 #PIA Port Forward' >> /etc/crontabs/root \
    && echo '0 */2 * * * /usr/bin/port-forwarding.sh | while IFS= read -r line; do echo "$(date) $line"; done >> /var/log/pia_portforward.log 2>&1 #PIA Port Forward' >> /etc/crontabs/root

COPY ./port-forwarding.sh /usr/bin/port-forwarding.sh
RUN chmod ug+x /usr/bin/port-forwarding.sh
RUN touch /var/log/pia_portforward.log

COPY ./entrypoint.sh /usr/bin/entrypoint.sh
RUN chmod ug+x /usr/bin/entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/entrypoint.sh"]
