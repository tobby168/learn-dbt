# 02 · Semantic layer 與 metrics

## 先分清楚兩件事

| | 本機 MetricFlow（`mf`） | dbt Semantic Layer（平台服務） |
|---|---|---|
| 做什麼 | 定義 semantic models 與 metrics，在命令列驗證和查詢 | 把同一份定義變成可被 BI 工具、API 查詢的服務 |
| 需要付費嗎 | **不用**，開源 | **要**，Starter 以上（Developer 免費方案沒有） |
| 本專案 | `make metrics-*` | 見 [03](03-dbt-platform.md) |

兩者吃的是同一份 YAML 定義，所以先在本機把 metrics 寫對，再決定要不要試用平台版。
來源：[Semantic Layer FAQs](https://docs.getdbt.com/docs/use-dbt-semantic-layer/sl-faqs)

## 這個專案怎麼定義

本專案使用 v2 的新版 YAML spec：semantic model 直接寫在 model 的 yml 裡，不再是獨立的頂層資源。
以 `models/marts/orders.yml` 為例（節錄並簡化排版）：

```yaml
models:
  - name: orders
    semantic_model:
      enabled: true               # 這個 model 同時是一個 semantic model
    agg_time_dimension: ordered_at
    columns:
      - name: order_id
        entity: {type: primary, name: order_id}      # 主鍵 → 其他 model 可以 join 進來
      - name: customer_id
        entity: {type: foreign, name: customer}      # 外鍵 → 連到 customers
      - name: ordered_at
        granularity: day
        dimension: {type: time}                      # 時間維度
      - name: is_food_order
        dimension: {type: categorical}               # 類別維度
    metrics:
      - name: orders
        type: simple
        agg: sum
        expr: 1                                      # 每列算 1 → 訂單數
      - name: food_orders
        type: simple
        agg: sum
        expr: 1
        filter: "{{ Dimension('order_id__is_food_order') }} = true"

saved_queries:
  - name: order_metrics                              # 存起來的常用查詢，可設定 exports
```

四種 metric 類型在專案裡都有範例：

| 類型 | 例子 | 位置 |
|---|---|---|
| `simple`（聚合一個欄位） | `orders`、`order_total`、`new_customer_orders`（帶 filter） | `orders.yml` |
| `ratio`（分子 ÷ 分母） | `food_revenue_pct` | `order_items.yml` |
| `derived`（用其他 metrics 運算） | `revenue_growth_mom`（用 `offset_window` 取上個月）、`average_order_value` | `order_items.yml`、`customers.yml` |
| `cumulative`（累計） | `cumulative_revenue` | `order_items.yml` |

## 本機工作流程

metrics 是 `mf` 讀 dbt 產出的 manifest，所以**改了 YAML 要先 `dbt parse`**，`mf` 才看得到
（本專案實測：沒 parse 時新增的 metric 不會出現）。Makefile 已經把 `parse` 放在 metrics 相關 target 前面了：

```bash
make metrics-list        # 列出所有 metrics
make metrics-validate    # 驗證 semantic models / metrics，並對 DuckDB 實際檢查
make metrics-query       # 範例查詢：每月訂單數與營收
```

直接用 `mf`（先 `source .venv-mf/bin/activate`，記得先 `dbt parse` 或 `make parse`）。以下都實測過：

```bash
mf list dimensions --metrics orders
mf query --metrics orders,order_total --group-by metric_time__month --order metric_time__month --limit 6
mf query --metrics order_total,new_customer_orders --group-by order_id__is_food_order
mf query --metrics revenue,revenue_growth_mom --group-by metric_time__month --limit 4
mf query --metrics food_revenue_pct,drink_revenue_pct --group-by metric_time__year
mf query --saved-query order_metrics --limit 3
mf query --metrics orders --group-by metric_time__month --explain    # 只看 MetricFlow 產生的 SQL
```

`--explain` 很值得看：它讓你看到「同一個 metric 定義」被編成什麼 SQL，這就是 semantic layer 的核心價值。

> **為什麼有兩個虛擬環境？** `dbt-metricflow` 依賴 dbt-core 1.x，裝在同一個環境會把 v2 的 `dbt`
> 指令蓋掉（實測 `dbt --version` 變成 1.12.5）。所以 dbt v2 在 `.venv-dbt`，MetricFlow 在 `.venv-mf`。
> 官方文件的做法也是在 v2 另外安裝 MetricFlow，並用 `mf` 前綴；`dbt sl` 是留給連上 dbt platform 的情況。
> 來源：[MetricFlow commands](https://docs.getdbt.com/docs/build/metricflow-commands)

## 練習

1. **加一個 simple metric。** 在 `orders.yml` 加 `small_orders`（訂單總額小於 20 的訂單數，
   filter 用 `{{ Dimension('order_id__order_total_dim') }} < 20`，可參考同檔的 `large_orders`）。
   `make metrics-validate` 後用 `mf query` 查。
2. **加一個 ratio metric。** `average_order_total` = `order_total` ÷ `orders`（`type: ratio`，
   `numerator`、`denominator`）。這個 metric 已用本專案驗證過寫法可行。
3. **故意寫錯。** 把 `numerator` 改成不存在的 metric 名稱，看 `make metrics-validate` 怎麼報錯。
4. **用 `--explain` 比較。** 比較 simple、ratio、cumulative 三種 metric 產生的 SQL 差在哪。

上一篇：[01 · Models](01-models.md)　下一篇：[03 · dbt platform](03-dbt-platform.md)
