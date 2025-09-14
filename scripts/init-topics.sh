#!/usr/bin/env bash
set -Eeuo pipefail

log(){ echo "[kafka-setup] $*"; }

log "Waiting for writer..."
for i in {1..90}; do
  if kafka-broker-api-versions --bootstrap-server broker-writer:9092 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

log "Waiting for reader..."
for i in {1..90}; do
  if kafka-broker-api-versions --bootstrap-server broker-reader:9092 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

log "Creating topics (RF=2, P=3)..."
kafka-topics --bootstrap-server broker-writer:9092 --create --if-not-exists \
  --topic demo-input  --replication-factor 2 --partitions 3 || true
kafka-topics --bootstrap-server broker-writer:9092 --create --if-not-exists \
  --topic demo-output --replication-factor 2 --partitions 3 || true

log "All topics are ready."
