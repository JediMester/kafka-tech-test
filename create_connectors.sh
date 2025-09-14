#!/usr/bin/env bash
#set -euo pipefail

# Note: jq opcionális - ha nincs telepítve, akkor a "| jq" helyett "|| true" működni fog szépen.

WRITER_URL=${WRITER_URL:-http://localhost:8083}
READER_URL=${READER_URL:-http://localhost:8084}

echo "[*] Creating FileStreamSource on connect-writer -> topic: demo-input"
curl -sS -X POST "${WRITER_URL}/connectors" -H 'Content-Type: application/json' -d '{
  "name": "filestream-source",
  "config": {
    "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
    "tasks.max": "1",
    "file": "/data/mock/mock_data.txt",
    "topic": "demo-input",
    "name": "filestream-source"
  }
}' | jq .

echo "[*] Creating FileStreamSink on connect-reader <- topic: demo-output"
curl -sS -X POST "${READER_URL}/connectors" -H 'Content-Type: application/json' -d '{
  "name": "filestream-sink",
  "config": {
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "tasks.max": "1",
    "topics": "demo-output",
    "file": "/data/out/output.txt",
    "name": "filestream-sink"
  }
}' | jq .

echo "[*] Done. Checking connectors:"
curl -sS "${WRITER_URL}/connectors" | jq .
curl -sS "${READER_URL}/connectors" | jq .
