FROM louislam/uptime-kuma:2.2.1

USER root
RUN mkdir -p /app/data/upload /app/data/screenshots /app/data/docker-tls \
    && chown -R node:node /app/data

COPY --chmod=755 entrypoint.sh /app/entrypoint.sh
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/app/entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
  CMD curl -f http://localhost:3001/ || exit 1
