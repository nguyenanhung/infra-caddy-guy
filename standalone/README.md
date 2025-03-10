# README

Build caddy container command

```shell
docker run -d \
  --name "bear_caddy" \
  --restart unless-stopped \
  --network "bear_caddy_net" \
  -p 80:80 \
  -p 443:443 \
  -v "./Caddyfile:/etc/caddy/Caddyfile" \
  -v "./sites:/etc/caddy/sites" \
  -v "./caddy_data:/data" \
  -v "./caddy_config:/config" \
  -v "/home/infra-caddy-sites:/var/www" \
  --add-host "host.docker.internal:host-gateway" \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --health-cmd "pgrep caddy" \
  --health-interval=30s \
  --health-retries=3 \
  --health-start-period=10s \
  "caddy:latest"
```
