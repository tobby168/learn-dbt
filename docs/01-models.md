# 01 · Models

這個專案是 [dbt-labs/jaffle-shop](https://github.com/dbt-labs/jaffle-shop)（`main` 分支，需要 dbt v2），
一家虛構三明治店的訂單資料。先跑通 `make all`，再照下面的順序讀。

## 資料怎麼流動

```
seeds/jaffle-data/*.csv ──dbt seed──▶ raw.raw_*            (source: ecom)
                                         │
                                         ▼
                     models/staging/stg_*.sql  (view：改名、轉型、金額 cents→dollars)
                                         │
                                         ▼
                     models/marts/*.sql        (table：orders、order_items、customers、
                                                locations、products、supplies)
```

| 位置 | 內容 |
|---|---|
| `seeds/jaffle-data/` | 一年份的假資料。正常 seed 是拿來放小型對照表，這裡借用它來「載入資料」，所以預設是停用的，要加 `--vars '{"load_source_data": true}'` 才會載入（見 `dbt_project.yml`）。 |
| `models/staging/__sources.yml` | 宣告 source `ecom.raw_*`，model 用 `{{ source('ecom', 'raw_orders') }}` 引用。 |
| `models/staging/stg_*.sql` | 一個 source 對一個 staging model，只做改名和轉型。 |
| `models/marts/*.sql` | 給分析用的寬表。`metricflow_time_spine` 是 MetricFlow 做時間運算用的日期表。 |
| `models/**/*.yml` | 欄位說明、tests、unit tests，以及下一篇的 semantic models 和 metrics。 |
| `macros/cents_to_dollars.sql` | 用 `adapter.dispatch` 依不同資料庫換寫法的 macro。 |
| `macros/generate_schema_name.sql` | 控制 model 建到哪個 schema：seed 進 `raw`；非 `prod` target 全部建在 `target.schema`；`prod` 才會加上自訂 schema 前綴。 |
| `profiles.yml` | 本機 DuckDB 連線（資料庫檔案 `jaffle_shop.duckdb`）。 |

materialization 在 `dbt_project.yml` 設定：staging 是 `view`，marts 是 `table`。

## 常用指令

以下都在本專案實測過（先 `make setup deps seed`；直接用 dbt 時請先
`source .venv-dbt/bin/activate`）：

```bash
dbt ls --select marts                 # 列出 marts 的 models、tests、unit tests
dbt show --select orders --limit 3    # 不建表，直接預覽 model 的查詢結果
dbt build --select +orders            # 建 orders 和它所有上游，並跑相關 tests
dbt compile --select stg_orders       # 看 Jinja 編譯後的 SQL（在 target/compiled/）
dbt build                             # 全部：13 個 models、27 個 tests、3 個 unit tests
```

## 練習

1. **讀 DAG。** 打開 `models/marts/orders.sql`，找出它 `ref` 了哪些 model，再看 `orders.yml` 裡的
   tests 在檢查什麼（例如 `order_total = subtotal + tax_paid`）。
2. **讓測試失敗。** 把 `macros/cents_to_dollars.sql` 裡 `default__cents_to_dollars` 的 `100` 改成 `10`，
   跑 `dbt build`，觀察哪些 tests 和 unit tests 失敗、錯誤訊息長怎樣，然後改回來。
3. **加一個 staging 欄位。** 在 `stg_orders.sql` 加一個衍生欄位，用 `dbt build --select stg_orders+`
   看下游怎麼反應。
4. **改成 incremental。** 把 `orders` 改成 incremental model，思考 `unique_key` 和增量條件要怎麼設，
   並用 `--full-refresh` 比對結果。本機 DuckDB 可以直接做；如果之後在 BigQuery **沙盒**（沒開 billing）
   上做，incremental 需要 DML，會失敗，細節見 [03](03-dbt-platform.md)。

## v2 + DuckDB 的已知限制（出自官方文件）

- v2 內建的 DuckDB driver **不支援載入 extension**（例如 `httpfs`、`parquet`、`spatial`）。需要時要另外用
  `dbc` 安裝 driver。
- v2 會做 SQL 靜態分析。如果 model 用 `read_csv()` 之類直接讀本地檔案，可能出現型別推斷的警告，
  即使實際執行是成功的。
- v2 的 DuckDB adapter 和 v1 的 `dbt-duckdb` 功能還沒完全對齊。

來源：[DuckDB setup](https://docs.getdbt.com/docs/local/connect-data-platform/duckdb-setup)

下一篇：[02 · Semantic layer 與 metrics](02-metrics.md)
