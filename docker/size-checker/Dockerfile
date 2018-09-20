FROM alpine:3.8

VOLUME /hdd
VOLUME /etc/ssmtp/

RUN apk update && apk add ssmtp

COPY ./sizeCheck.sh /

CMD /sizeCheck.sh
