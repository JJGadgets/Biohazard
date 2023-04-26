# external-proxy-x

## What is this?

This HAProxy is deployed in-cluster, allowing an external host (e.g. VPS, EC2) to run HAProxy with PROXY protocol encoding and send HTTP/S traffic in TCP mode to the external-proxy-x HAProxy.

external-proxy-x will then accept the TCP connection with PROXY protocol, decrypt the HTTPS traffic, add X-Forwarded-For header based on the PROXY protocol data, and re-encrypt the HTTPS traffic to send to ingress-nginx which is the actual Ingress controller that routes to apps.

Deploying external-proxy-x will allow ingress-nginx to be deployed without any TCP + PROXY listener looping hackiness, and allows ingress-nginx to listen without PROXY. This is important if other proxies that don't support PROXY but support X-Forwarded-For are in use (e.g. CloudFlare).

## Why the name?

Because I'm basically using HAProxy for **__external__** (public) ingress traffic, to translate **__PROXY__** protocol source IP data to **__X__**-Forwarded-For header data. Thus, **__external-proxy-x__**.
