FROM node:24-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        calibre \
        ffmpeg \
        libimage-exiftool-perl \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache

WORKDIR /app
COPY package.json ./
COPY app.js ./
COPY lib ./lib

RUN mkdir -p /inbox /inbox/archive /state /books /transmission/books \
    && chown -R 1000:1000 /app /inbox /state /books /transmission

USER 1000:1000

CMD ["node", "app.js"]
