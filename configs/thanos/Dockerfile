FROM quay.io/thanos/thanos:v0.35.0

COPY objstore.yaml   /etc/thanos/objstore.yaml
COPY entrypoint.sh   /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 9091 10901 10902

ENTRYPOINT ["/entrypoint.sh"]
