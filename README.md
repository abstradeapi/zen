docker run -d \
  --name=webtop \
  --security-opt seccomp=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Etc/UTC \
  -e SUBFOLDER=/ \
  -e TITLE=Webtop \
  -p 3000:3000 \
  -p 3001:3001 \
  --shm-size="8gb" \
  --restart unless-stopped \
  tibynx/webtop:ubuntu






lscr.io/linuxserver/chrome:latest








