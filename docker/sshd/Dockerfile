FROM sickp/alpine-sshd:latest

RUN apk update \
    && apk add --no-cache \
        sudo nano screen bash rsync rdiff-backup \
    && rm -rf /tmp/* /var/tmp/*

COPY ./createUsers.sh /createUsers.sh
COPY ./users.conf /users.conf
RUN chmod +x createUsers.sh && \
    ./createUsers.sh && \
    rm -f /createUsers.sh && \
    rm -f /users.conf && \
    passwd -d root && \
    echo "%wheel ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
