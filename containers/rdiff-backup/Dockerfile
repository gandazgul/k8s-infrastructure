FROM alpine:3.21.3

VOLUME /media/main
VOLUME /media/backup

# Docs: https://www.nongnu.org/rdiff-backup/docs.html
RUN apk update && apk add --no-cache rdiff-backup && rm -rf /tmp/* /var/tmp/*

ENTRYPOINT ["rdiff-backup", "-v5"]
