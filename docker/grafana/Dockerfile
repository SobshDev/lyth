FROM grafana/grafana:11.5.2

ENV GF_USERS_ALLOW_SIGN_UP=false

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
  CMD wget --spider -q http://localhost:3000/api/health
