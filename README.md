# learn-dbt

用 **dbt v2 + DuckDB + jaffle-shop** 學習 dbt 的 models、semantic layer、metrics、部署與 production job。

專案內容來自 [dbt-labs/jaffle-shop](https://github.com/dbt-labs/jaffle-shop)（`main` 分支，需要 dbt >= 2.0.0），
和上游的差異：

- 加上本機 DuckDB 的 `profiles.yml`，不需要 warehouse 帳號就能跑。
- 移除上游 `dbt_project.yml` 的 `dbt-cloud` project-id，以及上游的 CI/CD workflow
  （它們寫死了 dbt Labs 自己的 account 和 job ID）。
- 移除沒有用到的 `dbt-audit-helper`（原本追蹤沒有 pin 版本的 `main`）。
- 新增 `Makefile`、GitHub Actions CI 和 `docs/` 學習指南。

## 快速開始（本機）

需要 Python 3 和 make。已在 Python 3.11 上驗證。

```bash
make setup             # 建立兩個 virtualenv：dbt v2 與 MetricFlow
make deps              # 安裝 dbt_utils
make seed              # 把範例資料載入本機 DuckDB
make build             # 13 個 models + 27 個 tests + 3 個 unit tests
make metrics-validate  # 驗證 semantic models 和 metrics
make metrics-query     # 查詢範例：每月訂單數與營收
```

`make all` 會依序執行 setup → deps → seed → build → metrics-validate。`make help` 列出所有指令。

## 連 BigQuery

已用 BigQuery（billing 已啟用、location US）實測通過：6 seeds + 13 models + 27 tests + 3 unit tests，
`mf validate-configs` 0 errors。

```bash
brew install --cask google-cloud-sdk
gcloud auth login && gcloud auth application-default login   # dbt 用 ADC，不需要 JSON key
gcloud projects create <project-id> && gcloud billing projects link <project-id> --billing-account=<id>
gcloud services enable bigquery.googleapis.com bigquerystorage.googleapis.com --project=<project-id>
bq --project_id=<project-id> mk --dataset --location=US <project-id>:raw
bq --project_id=<project-id> mk --dataset --location=US <project-id>:prod
cp .env.example .env   # 填入 GCP_PROJECT_ID，.env 不會被 commit
make bq-all            # bq-check → bq-seed → bq-build → bq-metrics
```

連線設定全部來自 `.env`（`GCP_PROJECT_ID`、`BQ_DATASET`、`BQ_LOCATION`），見 `profiles.yml` 的 `bigquery` target。
跨 adapter 的踩坑紀錄見 [docs/04-bigquery-notes.md](docs/04-bigquery-notes.md)。

## 學習順序

| 主題 | 文件 | 需要 |
|---|---|---|
| Models、tests、macros | [docs/01-models.md](docs/01-models.md) | 本機（免費） |
| Semantic layer、metrics | [docs/02-metrics.md](docs/02-metrics.md) | 本機（免費） |
| Studio IDE、AI、部署、production job | [docs/03-dbt-platform.md](docs/03-dbt-platform.md) | dbt platform 帳號 + 雲端 warehouse |
| BigQuery 實測與踩坑 | [docs/04-bigquery-notes.md](docs/04-bigquery-notes.md) | GCP project |

## 專案結構

```
models/staging/   source 與 staging models（view）
models/marts/     分析用的 marts 與 metrics 定義（table）
seeds/            jaffle-shop 範例資料（預設停用，make seed 才會載入）
macros/           cents_to_dollars、generate_schema_name
profiles.yml      本機 DuckDB 與 BigQuery 連線（BigQuery 設定來自 .env）
.env.example      BigQuery 設定範本
Makefile          本機工作流程
.github/workflows/dbt-ci.yml   每次 push 跑一遍 make all
```

## 為什麼有兩個 virtualenv

`dbt-metricflow` 依賴 dbt-core 1.x，裝在同一個環境會蓋掉 v2 的 `dbt` 指令，
所以 dbt v2 放在 `.venv-dbt`，MetricFlow（`mf`）放在 `.venv-mf`。

## 注意

- **DuckDB 只能在本機（CLI）使用**，dbt platform 不支援。要練習平台功能請接
  Snowflake、BigQuery、Databricks 或 Redshift。細節見 [docs/03](docs/03-dbt-platform.md)。
- 本機的 `jaffle_shop.duckdb` 和 `target/` 不會被 commit。
