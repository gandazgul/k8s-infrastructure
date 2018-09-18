FROM sickp/alpine-sshd:latest

# TODO instead of getting the keys from github, mount a volume per user /home/user -> /media/main/gandazgul

VOLUME /home

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
