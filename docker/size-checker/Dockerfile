FROM alpine:3.8

VOLUME /hdd
VOLUME /etc/ssmtp/

RUN apk update && apk add --no-cache ssmtp && rm -rf /tmp/* /var/tmp/*

COPY ./sizeCheck.sh /

CMD /sizeCheck.sh
