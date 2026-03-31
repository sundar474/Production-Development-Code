FROM prom/node-exporter:v1.7.0

EXPOSE 9100

CMD ["--path.procfs=/host/proc", \
     "--path.rootfs=/rootfs", \
     "--path.sysfs=/host/sys", \
     "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"]
