# caddy-config
Used to deploy Caddy as webserver mapped to a configurable docker-compose deployment.


## Running Caddy

To run Caddy quickley from an immediate container:

```
docker run --name caddy-node -v /home/$USER/repos/:/repos --network <network-name> -p 80:80 -p 443:443 -it --entrypoint /bin/ash caddy
```

then in container as commands:

```
apk add tmux curl

tmux

```

then you can have Caddy running on one pannel while you request the API from the other pannel.

```
caddy run

&

curl 127.0.0.1:2019/load -X POST -H "Content-Type: application/json" -d "$(cat /repos/caddy/caddy.json)"

```
