# 04 · BigQuery 實測與踩坑紀錄

> **驗證狀態：** 2026-10-01 在已開 billing 的 GCP project（location US，ADC 認證）實測：`make bq-all`
> 全部通過（6 seeds、13 models、27 tests、3 unit tests，`mf validate-configs` 0 errors）。
> 沙盒（未開 billing）沒有測過。DuckDB 的 `make all` 在同一批修改後仍然通過，兩邊的 `orders`、`order_total` 數字一致。

## 為了讓 BigQuery 跑通做的修改

| 症狀（`mf validate-configs`） | 原因 | 修改 |
|---|---|---|
| `cumulative_revenue`：`<=` 比較 TIMESTAMP 與 DATE | BigQuery 的 seed 把 `ordered_at` 推成 DATETIME，`dbt.date_trunc` 在 BigQuery 回傳 TIMESTAMP，time spine 是 DATE，三種型別不相容（DuckDB 會隱式轉換所以沒事） | `metricflow_time_spine.sql` 的 `date_day` 與 `stg_orders.sql` 的 `ordered_at` 都明確 `cast(... as datetime)` |
| `revenue_growth_mom`：`=` 比較 DATETIME 與 TIMESTAMP | MetricFlow 對 offset window 會把月份 cast 成 DATETIME | 同上，整條時間欄位統一成 DATETIME |
| `median_revenue`：只支援近似連續百分位 | v2 新語法**不吃**舊的 `agg_params.use_approximate_percentile`（不報錯，靜默丟掉） | 改成 `agg: percentile`、`percentile: 0.5`、`percentile_type: continuous` |

結論：跨 adapter 的 semantic layer，時間欄位型別要在 staging 層就明確固定，不要依賴 adapter 預設行為。

## 本機工作流程

BigQuery 設定全部來自 `.env`（範本見 `.env.example`）：`GCP_PROJECT_ID`、`BQ_DATASET`、`BQ_LOCATION`。
`profiles.yml` 的 `target` 讀 `DBT_TARGET`（預設 `dev` = DuckDB），`make bq-*` 會切到 `bigquery`。

## 犯過的錯（以後不要再犯）

1. **zsh 的 `$P:raw` 會被當成 `:r` 修飾詞**，把 `raw` 吃成 `aw`，建出名稱錯誤的 dataset 指令。
   變數後面接冒號時一律寫 `${P}:raw`。
2. **`mf` 讀的是 `target/semantic_manifest.json` 最後一次寫入的內容。** 我先對 BigQuery `dbt parse`，
   接著跑 DuckDB 的 `make metrics-validate`（它也會 parse，覆蓋 manifest），再拿 BigQuery 去跑 `mf`，
   結果 135 個「Unable to access semantic model」都是假錯誤（relation 還是 DuckDB 的 `"jaffle_shop"."main"`）。
   現在 `make bq-metrics` 把 parse 和 validate 綁在同一個 target 裡；手動測的時候也一定要在同一個
   `DBT_TARGET` 下連續 parse 再 mf。看到成片的 access 錯誤，先檢查 manifest 的 `relation_name`。
3. **看到一個型別錯誤就猜修法，沒先看實際欄位型別。** 應該先用 `bq show --schema` 比對各層的型別，
   再一次修對，而不是改一個錯一個。
4. **一次印出 135 行驗證錯誤。** 先用 `grep -c`／`head` 看總數和第一個錯誤，再往下查。
