FROM louislam/uptime-kuma:2.2.1

RUN mkdir -p /app/data/upload /app/data/screenshots /app/data/docker-tls

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
  CMD curl -f http://localhost:3001/ || exit 1
