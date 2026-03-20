FROM grafana/loki:3.4.3

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
  CMD wget --spider -q http://localhost:3100/ready
