# Kafka Tech Test -> Two-broker cluster + Kafka Connect (writer/reader roles)

## Overview
This project spins up a **two-broker Kafka cluster** with **Zookeeper**, and two **Kafka Connect** workers with separated roles:

- **Broker roles:**  
  - `broker-writer` - used by the **producer** side (FileStreamSource).  
  - `broker-reader` - used by the **consumer** side (FileStreamSink).
- **Connect roles:**  
  - `connect-writer` connects only to `broker-writer`, runs **FileStreamSource** reading a local file.  
  - `connect-reader` connects only to `broker-reader`, runs **FileStreamSink** writing to a local file.
- Topics created with **replication factor = 2**.
- A simple **forwarder** pipes `demo-input` -> `demo-output` on the reader side to fulfil the “different output topic” requirement.

**End-to-end flow:**  
`data/mock/mock_data.txt` -> FileStreamSource -> `demo-input` -> forwarder -> `demo-output` -> FileStreamSink -> `data/out/output.txt`

### Services:
- zookeeper
- broker-writer (Kafka broker #1)
- broker-reader (Kafka broker #2)
- kafka-setup (creates topics with RF=2)
- connect-writer (FileStreamSource -> demo-input)
- connect-reader (FileStreamSink <- demo-output)
- topic-forwarder (demo-input -> demo-output)


## Prerequisites
- Docker and Docker Compose v2
- `curl`, `jq` (optional for pretty JSON)
- Linux/macOS terminal

## Quick start
```sh
# 0) Prepare mounts
mkdir -p data/mock data/out plugins/connect-file
cp mock_data.txt data/mock/

# 1) Start everything
docker compose up -d

# 2) Install connectors via REST (creates FileStreamSource/Sink)
chmod +x ./create_connectors.sh
./create_connectors.sh

# 3) Verify end-to-end
echo "e2e-$(date +%s)" >> data/mock/mock_data.txt
tail -n 5 data/out/output.txt
```

NOTE: You should see the line appear in `data/out/output.txt`


## Replication proof

Topics are created with RF=2 and spread across both brokers.

```sh
# Check topic metadata (replicas/leaders/ISR)
docker compose exec broker-reader bash -lc \
  "kafka-topics --bootstrap-server broker-reader:9092 --describe --topic demo-input"
```

## Failover demo (leader re-election)

```sh
# Stop the writer broker
docker compose stop broker-writer
sleep 5

# Leaders move (expect Leader=2 for partitions)
docker compose exec broker-reader bash -lc \
  "kafka-topics --bootstrap-server broker-reader:9092 --describe --topic demo-input | grep -E 'Partition|Leader|Isr'"

# Sink continues to consume on reader side
# (New lines will be produced again once writer is back)
docker compose start broker-writer
```

Connect REST

- Writer Connect: http://localhost:8083

- Reader Connect: http://localhost:8084

The script `create_connectors.sh` posts:

- filestream-source on writer -> demo-input

- filestream-sink on reader -> demo-output

List available plugins:
```sh
curl -s http://localhost:8083/connector-plugins | jq '.[].class'
curl -s http://localhost:8084/connector-plugins | jq '.[].class'
# expect: org.apache.kafka.connect.file.FileStreamSourceConnector/SinkConnector
```

### Directory layout
```sh
.
├─ docker-compose.yaml
├─ create_connectors.sh
├─ mock_data.txt                 # sample data
├─ data/
│  ├─ mock/                      # mounted into connect-writer
│  │  └─ mock_data.txt
│  └─ out/                       # sink writes here
│     └─ output.txt
└─ plugins/
   └─ connect-file/
      └─ connect-file-3.6.1.jar  # FileStream plugin (Java 11 compatible)
```

## Design notes
- Broker role split demonstrates producer/consumer segregation and still shows replication: when one broker is down, the other serves reads.

- Replication factor = 2: topic availability during broker failure (leader re-election).

- Connect split: each worker uses a single broker endpoint to enforce the “writer only” vs “reader only” requirement.

- Forwarder uses a simple “consumer -> producer” pipe to route demo-input -> demo-output.

- Healthchecks and startup waits reduce race conditions in local Compose environments.

## Troubleshooting

### 1. FileStream connector not visible in plugin list
Confluent Connect images don’t ship the “connect-file” plugin.
Fix:

- Download connect-file-3.6.1.jar (Kafka 3.6 / Java 11 compatible) to ./plugins/connect-file/.
- Ensure: CONNECT_PLUGIN_PATH=/plugins,/usr/share/java,/usr/share/confluent-hub-components
- Mount: ./plugins:/plugins:ro
- Restart Connect, then:
```sh
curl -s http://localhost:8083/connector-plugins | jq '.[].class' | grep FileStream
```

### 2. `kafka-setup` “syntax error near `done'”
The command used `command: >` which folds lines into one.
Fix: use `command: |` (literal block), remove outer quotes, and keep the loop on multiple lines.

### 3. Forwarder keeps restarting
The `console-consumer | console-producer` pipeline may exit when metadata/pipe closes.
Fix: run inside a `while true` loop (see compose), or switch to `kcat`-based forwarder (stable).

### 4. Topics don’t exist
Run the following manual command:
```sh
docker compose exec broker-writer bash -lc \
  "kafka-topics --bootstrap-server broker-writer:9092 --create --if-not-exists --topic demo-input --replication-factor 2 --partitions 3"
docker compose exec broker-writer bash -lc \
  "kafka-topics --bootstrap-server broker-writer:9092 --create --if-not-exists --topic demo-output --replication-factor 2 --partitions 3"
```

## Makefile targets

The `Makefile` provides quick commands for setting up and testing the solution - it is included in the root dir.

```makefile
DOCKER ?= docker compose
ENV   ?= ./
MOCK  ?= data/mock/mock_data.txt
OUT   ?= data/out/output.txt

.PHONY: up down ps logs writer-logs reader-logs connect-logs fw-logs \
        topics list desc connectors rm-connectors prove failover \
        restart-forwarder reset-out nuke help

help:
	@echo "Targets: up, down, ps, logs, writer-logs, reader-logs, connect-logs, fw-logs"
	@echo "         list, desc, connectors, rm-connectors, prove, failover"
	@echo "         restart-forwarder, reset-out, nuke"

up:
	mkdir -p data/mock data/out plugins/connect-file scripts
	@if [ ! -f "$(MOCK)" ]; then cp mock_data.txt $(MOCK); fi
	$(DOCKER) up -d

down:
	$(DOCKER) down -v

ps:
	$(DOCKER) ps

logs:
	$(DOCKER) logs -f

writer-logs:
	$(DOCKER) logs -f broker-writer

reader-logs:
	$(DOCKER) logs -f broker-reader

connect-logs:
	$(DOCKER) logs -f connect-writer connect-reader

fw-logs:
	$(DOCKER) logs -f topic-forwarder

list:
	$(DOCKER) exec broker-writer bash -lc "kafka-topics --bootstrap-server broker-writer:9092 --list || true"
	$(DOCKER) exec broker-reader bash -lc "kafka-topics --bootstrap-server broker-reader:9092 --list || true"

desc:
	$(DOCKER) exec broker-writer bash -lc "kafka-topics --bootstrap-server broker-writer:9092 --describe --topic demo-input || true"
	$(DOCKER) exec broker-reader bash -lc "kafka-topics --bootstrap-server broker-reader:9092 --describe --topic demo-input || true"

connectors:
	chmod +x ./create_connectors.sh
	./create_connectors.sh

rm-connectors:
	- curl -s -X DELETE http://localhost:8083/connectors/filestream-source | jq . || true
	- curl -s -X DELETE http://localhost:8084/connectors/filestream-sink   | jq . || true

prove:
	@echo "proof-$$(date +%s)" >> $(MOCK)
	@sleep 1
	@echo "Last 5 lines in $(OUT):"; tail -n 5 $(OUT) || true

failover:
	@echo "Stopping writer..."
	$(DOCKER) stop broker-writer
	@sleep 5
	@echo "Leaders after writer stop:"
	$(DOCKER) exec broker-reader bash -lc "kafka-topics --bootstrap-server broker-reader:9092 --describe --topic demo-input | grep -E 'Partition|Leader|Isr'"
	@echo "Starting writer..."
	$(DOCKER) start broker-writer
	@sleep 5
	@echo "Leaders after writer start:"
	$(DOCKER) exec broker-reader bash -lc "kafka-topics --bootstrap-server broker-reader:9092 --describe --topic demo-input | grep -E 'Partition|Leader|Isr'"

restart-forwarder:
	$(DOCKER) restart topic-forwarder

reset-out:
	@echo -n '' > $(OUT) || true
	@echo "Cleared $(OUT)"

nuke: down
	@echo "All containers and volumes removed."
```
### How to use - a couple of examples:
```sh
# creates the necessarey directories - if they don't yet exist - and starts the containers
make up
# creates the connectors
make connectors
# creates the failover mechanism that demonstrates successful leader switching
make failover
# topic listing
make list
# describe topics
make desc
```

## Time spent on the solution
- Design & Compose: ~4 hours

- Debug & docs: ~5 hours
