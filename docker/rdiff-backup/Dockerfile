FROM alpine:3.8

VOLUME /media/main
VOLUME /media/backup

# Docs: https://www.nongnu.org/rdiff-backup/docs.html
RUN apk update && apk add --no-cache rdiff-backup && rm -rf /tmp/* /var/tmp/*

CMD rdiff-backup -v5 /media/main /media/backup
