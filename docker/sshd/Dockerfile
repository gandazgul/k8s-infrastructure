FROM sickp/alpine-sshd:latest

COPY ./createUsers.sh /createUsers.sh
COPY ./users.conf /users.conf
RUN chmod +x createUsers.sh && \
    ./createUsers.sh && \
    rm -f /createUsers.sh && \
    rm -f /users.conf && \
    passwd -d root && \
    echo "%wheel ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN apk update && \
    apk add sudo nano
