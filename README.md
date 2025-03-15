# Infra Caddy Guy's Scripts

A lightweight Server management script set, backend is Docker, Caddy Web Server. Makes the life of the infra guy a
little simpler and easier.

![Screenshot](https://live.staticflickr.com/65535/54371975845_f827eeeb9c_b.jpg)

## Installation

```bash
git clone git@github.com:nguyenanhung/infra-caddy-guy.git && cd infra-caddy-guy && ./bin/enable-shortcut
```

and use it

```bash
infra-caddy introduce
```

## Guidelines

### Important note

#### If another container needs to connect to the Caddy Web Server network, it needs to connect to the Caddy Web Server network.

##### **Temporary/Short Term: Will be invalidated if restarted or down mode**

> `<container_name>` is the name of the container to connect to.

```shell
# Connect Caddy Network
docker network connect bear_caddy_net <container_name>
```

```shell
# Disconnect Caddy Network
docker network disconnect bear_caddy_net <container_name>
```

##### **Permanent (if using docker-compose)**

Add the network name of the Caddy Web Server to your `docker-compose.yml` file

```yaml
networks:
    # ...
    bear_caddy_net:
        external: true
    # ...
```

## Stack

- [x] Docker, fzf
- [x] Caddy Web Server: sites, reverse proxy, load balancer and basic authentication
- [x] Laravel Builder: Start from scratch with Laravel Framework Playbook, select version, worker and anything...
- [x] WordPress Builder: Start from scratch with WordPress and choose theme, plugins...
- [x] Static Site Server
- [x] Node.js Builder: Start from scratch with NestJS Playbook, select version, port and anything...
- [x] Node.js Application: Simple and lightweight connect Caddy Web Server with you Node.js Application
- [x] PHP Application Routing
- [x] Improve security (file, header) of common application: PHP, Node.js, SPA, Static site, Reverse Proxy

- [x] ... and others packages supporting, can be mentioned as `redis`, `memcached`, `mongodb`, `mariadb`, `mysql`,
  `percona`, `postgresql`, `influxdb`, `rabbitmq`, `beanstalkd`, `gearmand`, `elasticsearch`, `mailhog`, `phpmyadmin`,
  `adminer`, `uptime-kuma`, `n8n`, `minio`

## Deployment

- [ ] Blue/Green Rolling Deployment

## Integration

- [ ] Amazon Web Services CLI integration (`awscli`)

## Contact

| Name        | Email                | GitHub        | Facebook      |
|-------------|----------------------|---------------|---------------|
| Hung Nguyen | dev@nguyenanhung.com | @nguyenanhung | @nguyenanhung |

From 🐼 Bear Family with Love ♥️
