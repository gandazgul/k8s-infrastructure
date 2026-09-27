FROM docker.io/library/postgres:17-alpine

RUN apk add --no-cache bash

COPY backup.sh /usr/local/bin/postgres-backup

RUN chmod 755 /usr/local/bin/postgres-backup

ENTRYPOINT ["/usr/local/bin/postgres-backup"]
