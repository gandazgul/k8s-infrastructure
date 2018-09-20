#!/bin/sh

/etc/transmission/stop.sh
[ ! -f /opt/tinyproxy/stop.sh ] || /opt/tinyproxy/stop.sh
s6-setuidgid abc /usr/bin/flexget daemon stop

printf "To:$MAIL_TO" >> /tmp/mail.txt
printf "From:<Seedbox at k8s> $MAIL_TO" >> /tmp/mail.txt
printf "Subject:Seedbox: The VPN is down!\n\n" >> /tmp/mail.txt
LOG=`tail -100 /var/log/syslog`
printf "Check the seedbox. OpenVPN is down.\n\nLog:\n\n$LOG" >> /tmp/mail.txt

ssmtp -t < /tmp/mail.txt
rm -f /tmp/mail.txt
