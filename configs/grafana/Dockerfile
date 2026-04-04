FROM grafana/grafana:11.0.0

USER root

# Copy config and provisioning
COPY grafana.ini                        /etc/grafana/grafana.ini
COPY provisioning/datasources/          /etc/grafana/provisioning/datasources/
COPY provisioning/dashboards/           /etc/grafana/provisioning/dashboards/

# EFS is mounted at /var/lib/grafana by ECS task definition
# The access point sets uid/gid 472 (grafana) automatically
RUN mkdir -p /var/lib/grafana/dashboards \
    && chown -R 472:472 /var/lib/grafana /etc/grafana

USER grafana

EXPOSE 3000

CMD ["/run.sh"]
