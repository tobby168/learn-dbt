# Local workflow: dbt v2 + DuckDB + MetricFlow. Run `make help` for targets.
DBT_VENV := .venv-dbt
MF_VENV  := .venv-mf
DBT      := $(DBT_VENV)/bin/dbt
MF       := $(MF_VENV)/bin/mf

# Semantic manifest validation is done by `mf validate-configs` locally;
# without a dbt platform login dbt v2 would only print a warning about it.
export DBT_ENGINE_NO_WARN_SEMANTIC_MANIFEST_VALIDATION := 1

# BigQuery settings (GCP_PROJECT_ID, BQ_DATASET, BQ_LOCATION) live in .env, see .env.example.
-include .env
export
BQ_TARGET := bigquery

.DEFAULT_GOAL := help
.PHONY: help all setup deps seed build parse metrics-list metrics-validate metrics-query clean bq-check bq-seed bq-build bq-metrics bq-all

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

all: setup deps seed build metrics-validate ## Run the whole local flow (also what CI runs)

setup: $(DBT) $(MF) ## Create the two virtualenvs (dbt v2, MetricFlow)

$(DBT): requirements.txt
	python3 -m venv $(DBT_VENV)
	$(DBT_VENV)/bin/pip install --quiet -r requirements.txt
	@touch $@

$(MF): requirements-metricflow.txt
	python3 -m venv $(MF_VENV)
	$(MF_VENV)/bin/pip install --quiet -r requirements-metricflow.txt
	@touch $@

deps: $(DBT) ## Install dbt packages (dbt_utils)
	$(DBT) deps

seed: $(DBT) ## Load the jaffle-shop sample data into DuckDB (schema: raw)
	$(DBT) seed --full-refresh --vars '{"load_source_data": true}'

build: $(DBT) ## Build all models and run all tests and unit tests
	$(DBT) build

parse: $(DBT) ## Re-parse the project (refreshes the semantic manifest that mf reads)
	$(DBT) parse

metrics-list: $(MF) parse ## List the metrics defined in the project
	$(MF) list metrics

metrics-validate: $(MF) parse ## Validate semantic models and metrics against DuckDB
	$(MF) validate-configs

metrics-query: $(MF) parse ## Example metric query: orders and revenue by month
	$(MF) query --metrics orders,order_total --group-by metric_time__month --order metric_time__month --limit 6

bq-check: $(DBT) ## Verify the BigQuery connection (needs .env and `gcloud auth application-default login`)
	$(DBT) debug --target $(BQ_TARGET)

bq-seed: $(DBT) deps ## Load the sample data into BigQuery (dataset: raw)
	$(DBT) seed --target $(BQ_TARGET) --full-refresh --vars '{"load_source_data": true}'

bq-build: $(DBT) ## Build all models and run all tests against BigQuery
	$(DBT) build --target $(BQ_TARGET)

# parse and mf must use the same target: mf reads target/semantic_manifest.json as last written.
bq-metrics: $(DBT) $(MF) ## Validate semantic models and metrics against BigQuery
	DBT_TARGET=$(BQ_TARGET) $(DBT) parse
	DBT_TARGET=$(BQ_TARGET) $(MF) validate-configs

bq-all: bq-check bq-seed bq-build bq-metrics ## Run the whole flow against BigQuery

clean: ## Remove build output and the local DuckDB file (keeps the virtualenvs)
	rm -rf target dbt_packages logs jaffle_shop.duckdb jaffle_shop.duckdb.wal
