FROM prom/node-exporter:v1.8.0

# Node exporter is run as a DAEMON ECS service (one per EC2 host)
# Host filesystem is bind-mounted via ECS task definition volumes:
#   /proc  → /host/proc
#   /sys   → /host/sys
#   /      → /rootfs

EXPOSE 9100

ENTRYPOINT ["/bin/node_exporter"]
CMD [
  "--path.procfs=/host/proc",
  "--path.rootfs=/rootfs",
  "--path.sysfs=/host/sys",
  "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)",
  "--web.listen-address=0.0.0.0:9100"
]
