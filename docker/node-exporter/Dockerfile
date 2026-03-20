FROM prom/node-exporter:v1.9.0

LABEL traefik.enable=false

CMD ["--path.rootfs=/host", "--path.procfs=/host/proc", "--path.sysfs=/host/sys"]
