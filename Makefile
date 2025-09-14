# Config
DOCKER ?= docker compose
ENV   ?= ./
MOCK  ?= data/mock/mock_data.txt
OUT   ?= data/out/output.txt

# Phony
.PHONY: up down ps logs writer-logs reader-logs connect-logs fw-logs \
        topics list desc connectors rm-connectors prove failover \
        restart-forwarder reset-out nuke help

help:
	@echo "Targets:"
	@echo "  up                 - create dirs, up -d (force recreate if needed)"
	@echo "  down               - down -v"
	@echo "  ps                 - services status"
	@echo "  logs               - tail all logs"
	@echo "  writer-logs        - broker-writer logs"
	@echo "  reader-logs        - broker-reader logs"
	@echo "  connect-logs       - both connect logs"
	@echo "  fw-logs            - forwarder logs"
	@echo "  list               - list topics (writer & reader)"
	@echo "  desc               - describe demo-input (writer & reader)"
	@echo "  connectors         - create FileStream connectors via REST"
	@echo "  rm-connectors      - delete the connectors"
	@echo "  prove              - append a test line -> expect it in output"
	@echo "  failover           - stop writer, show new leaders, start writer"
	@echo "  restart-forwarder  - restart the forwarder service"
	@echo "  reset-out          - truncate sink output file"
	@echo "  nuke               - full cleanup (down -v)"
	@echo "  help               - this help"

up:
	mkdir -p data/mock data/out plugins/connect-file
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
	@echo "Connectors deletion attempted."

prove:
	@echo "proof-$$(date +%s)" >> $(MOCK)
	@sleep 1
	@echo "Last 5 lines in $(OUT):"
	@tail -n 5 $(OUT) || true

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
