#!/bin/sh
set -e

OBJSTORE_CONFIG="/etc/thanos/objstore.yaml"

case "$THANOS_TARGET" in
  query)
    echo "Starting Thanos Query..."
    exec /bin/thanos query \
      --http-address=0.0.0.0:9091 \
      --grpc-address=0.0.0.0:10901 \
      --store="$PROMETHEUS_ENDPOINT:10901" \
      --store.sd-dns-resolver=miekgdns \
      --query.replica-label=replica \
      --query.auto-downsampling \
      --log.level=info
    ;;

  compactor)
    echo "Starting Thanos Compactor..."
    exec /bin/thanos compact \
      --http-address=0.0.0.0:10902 \
      --data-dir=/var/thanos/compact \
      --objstore.config-file="$OBJSTORE_CONFIG" \
      --retention.resolution-raw=365d \
      --retention.resolution-5m=365d \
      --retention.resolution-1h=365d \
      --compact.concurrency=4 \
      --downsample.concurrency=4 \
      --delete-delay=48h \
      --wait \
      --log.level=info
    ;;

  *)
    echo "ERROR: THANOS_TARGET must be 'query' or 'compactor'. Got: '$THANOS_TARGET'"
    exit 1
    ;;
esac
