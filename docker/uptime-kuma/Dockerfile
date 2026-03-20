FROM louislam/uptime-kuma:1

LABEL traefik.enable=true

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
  CMD wget --spider -q http://localhost:3001/
