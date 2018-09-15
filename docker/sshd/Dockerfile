FROM sickp/alpine-sshd:latest

# TODO instead of getting the keys from github, mount a volume per user /home/user -> /media/main/gandazgul

VOLUME /home/gandazgul
VOLUME /home/rafag

RUN \
  passwd -d root && \
  adduser -D -s /bin/ash gandazgul && \
  passwd -u gandazgul && \
  addgroup gandazgul wheel && \
  adduser -D -s /bin/ash rafag && \
  passwd -u rafag && \
  addgroup rafag wheel && \
  echo "%wheel ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN apk update && \
    apk add sudo nano
