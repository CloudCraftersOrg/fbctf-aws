# ADR 002 — Internal NLB (L4) between nginx and HHVM

**Status:** Accepted (2026-08-26)

## Context
In fbctf's multi-server mode, nginx talks to HHVM over FastCGI on TCP 9000 (`extra/nginx/nginx.conf`: `fastcgi_pass HHVMSERVER:9000`; `provision.sh --hhvm-server <host>` seds the hostname in). FastCGI is not HTTP — an ALB (L7) cannot load-balance it.

## Decision
An internal Network Load Balancer (TCP:9000, TCP health check) fronts the HHVM ASG. The NLB DNS name is passed to the web tier as `--hhvm-server`, so provision wires nginx to it with no extra config patching.

## Consequences
- nginx resolves the NLB DNS once at config load; NLB IPs can drift over long uptimes. Acceptable for time-boxed demo runs — restart nginx if the app tier becomes unreachable after long uptime.
- The app-tier SG cannot reliably reference the web SG through an NLB; if client-IP preservation causes trouble, fall back to app-subnet CIDR rules.
