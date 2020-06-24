FROM dperson/openvpn-client

RUN \
    echo "**** Adding cronjob to keep the transmission port open *****" \
    && echo '@reboot sleep 120 && /vpn/port-forwarding.sh | while IFS= read -r line; do echo "$(date) $line"; done >> /var/log/pia_portforward.log 2>&1 #PIA Port Forward' >> /etc/crontabs/root \
    && echo '0 */2 * * * /vpn/port-forwarding.sh | while IFS= read -r line; do echo "$(date) $line"; done >> /var/log/pia_portforward.log 2>&1 #PIA Port Forward' >> /etc/crontabs/root

COPY ./port-forward-cron.sh /usr/bin/port-forward-cron.sh
RUN chmod ug+x /usr/bin/port-forward-cron.sh
COPY ./entrypoint.sh /usr/bin/entrypoint.sh
RUN chmod ug+x /usr/bin/entrypoint.sh

RUN touch /var/log/pia_portforward.log

ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/entrypoint.sh"]
