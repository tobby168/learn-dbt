# 03 · dbt platform：Studio IDE、AI、部署與 production job

> **驗證狀態（2026-10-01）：** 01、02 篇的指令都在本機實測過。BigQuery、Studio IDE 的
> `dbt deps` / `dbt seed` / `dbt build`、Production environment 與 job 的 **Run now**，以及
> Looker Studio 連 `prod` 都已用 Developer 方案實際跑通（由使用者操作平台，BigQuery 端由我用 gcloud/bq 驗證）。
> 其餘部分（Wizard、排程、Starter 的 Semantic Layer、CI job）沒有實測，步驟來自官方文件
> 和 jaffle-shop 上游 README，實際畫面可能有出入，以官方文件為準。

## 方案與限制（來自[官方定價頁](https://www.getdbt.com/pricing)）

| | Developer（免費） | Starter（$100 / 人 / 月） |
|---|---|---|
| Seats / Projects | 1 / 1 | 5 / 1 |
| 每月成功建置的 models | 3,000 | 15,000 |
| 瀏覽器版 Studio IDE | ✅ | ✅ |
| Job scheduling 與監控 | ✅ | ✅ |
| GitHub / GitLab 的 CI checks | ✅ | ✅ |
| dbt Semantic Layer（metrics 對外服務） | ❌ | ✅（每月 5,000 次 queried metrics） |
| dbt Catalog、API 存取 | ❌ | ✅ |

- Developer 超過 3,000 個 models 後，**之後的 run 會被取消**，直到下個月重置或升級；平台其他功能和既有工作都還在。
  （[Plans and billing](https://docs.getdbt.com/docs/platform/billing/plans-and-billing)）
- 估算：本專案一次 `dbt build` 約建 13 個 models，每天跑一次綽綽有餘；每小時跑一次一個月會到
  13 × 24 × 30 = 9,360，會超過。seeds 是否計入 models 數我沒查到，請以平台上的用量頁面為準。
- Starter 有試用，但官方定價頁**沒有標示天數**（頁面上的「30 day free trial」是 dbt State 的），
  請以註冊時看到的為準。

## 一定要先知道的限制

1. **DuckDB 在 dbt platform 是「CLI only」，平台不能連。** dbt platform 上的 v2 支援 Snowflake、
   Amazon Redshift、Databricks、Google BigQuery（ClickHouse 為 private beta）。所以練習 Studio IDE
   和 production job 時，要準備其中一種雲端 warehouse（免費方案見下一節）。
   （[About connections](https://docs.getdbt.com/docs/cloud/connect-data-platform/about-connections)、
   [Supported data platforms](https://docs.getdbt.com/docs/supported-data-platforms)）
2. **Environment 的 dbt 版本要選 v2.0.0 以上。** 本專案的 `dbt_project.yml` 有
   `require-dbt-version: ">=2.0.0"`，選到 v1.x 會在版本檢查時失敗。
3. **本機的 `profiles.yml` 在平台上沒有作用**，平台使用你在 Account settings → Connections 設定的連線。

## Studio IDE 跑在哪裡

Studio IDE 是 dbt platform 託管的網頁應用，在你筆電的瀏覽器裡開啟，直接連你的 GitHub repo 和
warehouse。它**不會連到我（Claude）的雲端環境**，我的環境只是用來寫程式和推送；
只要程式碼在 GitHub 上，任何一台能上網的電腦都能用。官方列出的前置條件：

- dbt 帳號和一個 Developer seat
- 一個 git repo，且 git provider 要有**寫入權限**（連 GitHub 是安裝 dbt 的 GitHub App）
- 專案已連到 warehouse，並設定好開發環境和個人憑證
- 建議關閉廣告攔截器：有些檔名（例如 `google_adwords.sql`）會被誤判成廣告而攔掉

要注意的是：**這個專案目前在分支 `claude/ecstatic-goldberg-xdtgie`，還沒進 `main`。**
Production environment 要跑 `main`，Studio 預設開的也是預設分支，所以要先把分支合併進 `main`。

來源：[Studio IDE](https://docs.getdbt.com/docs/cloud/studio-ide/develop-in-studio)、
[Connect GitHub](https://docs.getdbt.com/docs/cloud/git/connect-github)

## 哪個 warehouse 有免費方案

| Warehouse | 免費方案 | 備註 |
|---|---|---|
| **BigQuery（建議）** | 免費額度**長期有效**：每月 10 GiB 儲存、1 TiB 查詢。另有 sandbox 模式，不需信用卡或 billing 帳號 | sandbox 有限制，見下方 |
| Snowflake | 30 天試用、$400 額度，註冊不需付款資訊 | 倒數型，到期或額度用完就要付費 |
| Redshift Serverless | $300 額度，90 天內使用（限從沒用過 Redshift Serverless 的帳號） | 倒數型，需要 AWS 帳號 |
| Databricks | 有 Free Edition，但只有一個 2X-Small SQL warehouse，且對外連線限於少數信任網域 | 我沒查到 dbt platform 能不能連到 Free Edition，**不建議** |

建議 BigQuery：額度不會倒數、dbt 官方的 BigQuery quickstart 就是用它，而且上游 jaffle-shop 有
BigQuery 版本的 macro（`bigquery__cents_to_dollars`）。
來源：[BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox)、
[BigQuery pricing](https://cloud.google.com/bigquery/pricing)、
[AWS Redshift free trial](https://aws.amazon.com/redshift/free-trial/)、
[Snowflake trial accounts](https://docs.snowflake.com/en/user-guide/admin-trial-account)、
[Databricks Free Edition 限制](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)

### BigQuery sandbox 的限制

沙盒不需要信用卡，但有這些限制：

- 終身 10 GiB 儲存額度（刪除資料也不會退還）；所有 tables、views 預設 **60 天後自動過期**。
- **不支援 DML 語句和 streaming。**

對本專案的影響：

- `dbt build` 建 view 和 table 用的是 DDL，不受影響（dbt 官方 quickstart 就是在沒開 billing 的專案做的）。
- **incremental model 和 snapshot 需要 DML**，在沙盒會失敗，所以 [01](01-models.md) 的練習 4 要先升級。
- seed 在「v2 + BigQuery 沙盒」下能不能載入，**沒有驗證**：本專案實測用的是已開 billing 的專案（見 [04](04-bigquery-notes.md)）。
  如果在沙盒 `dbt seed` 失敗，請升級。
- 升級的做法是替專案開 billing 帳號。Google 說明開了之後，免費額度仍然保留，超過才收費；
  本專案的資料只有約 16 MB，遠低於額度。建議在 Google Cloud 設定預算提醒。

## AI 功能：dbt Wizard 與 dbt Copilot

| | 說明 |
|---|---|
| **dbt Wizard** | 官方目前推薦在 Studio IDE 使用的 AI agent：能理解專案脈絡、多步驟修改並驗證，可以產生 SQL、docs、tests、semantic models 和 metrics。依 token 計費。 |
| **dbt Copilot** | 較早的單鍵產生 docs、tests、semantic models 的功能，另外以「次數」計費，不用 Wizard 的額度。 |

Wizard 的免費額度（[官方 FAQ](https://docs.getdbt.com/docs/dbt-ai/wizard-billing-faqs)）：

- Developer 和 Starter 帳號有 **$100 額度、30 天內免費**，以帳號為單位；額度用完或滿 30 天就結束，不累積。
- **試用需要商務 email，Gmail 等個人信箱不符合資格**，而且要由帳號的 admin 或 billing admin 啟動。
  如果你只有個人信箱，這個試用可能開不了。
- 試用結束後，平台託管的 Wizard 會暫停，除非加入付款方式並設定每月上限；也可以改用
  **自備 API key（BYOK）**，由你的 AI 供應商直接計費，不消耗 dbt 的額度。
- 2026-09-01 起 AI 功能預設為開啟（陸續推出到既有帳號），帳號 admin 可以在 Account settings 開關；
  開啟本身不會產生費用。

建議用法：先在沒有 AI 的情況下完成 [01](01-models.md) 和 [02](02-metrics.md)，再請 Wizard 做同樣的事
（例如「為 `stg_orders` 加 tests」、「新增一個 ratio metric」），把結果和自己寫的比較，才看得出
它哪裡幫得上忙、哪裡需要你把關。

## 部署步驟

### 1. 準備 BigQuery 和 dbt platform

以下依 [dbt 的 BigQuery quickstart](https://docs.getdbt.com/guides/bigquery) 和
[連線文件](https://docs.getdbt.com/docs/cloud/connect-data-platform/connect-bigquery)整理：

1. 用 Google 帳號進 BigQuery Console，建立一個新的 GCP project（先不用開 billing）。
2. 建立 dataset：`raw`（seed 載入的位置）和 `prod`（Prod environment 的 schema）。
   location 維持預設的 US；建議同一個專案的 dataset 都放同一個 location，避免跨 location 的查詢失敗。
3. 建立 service account（例如 `dbt-user`），角色給 **BigQuery Job User** 和 **BigQuery Data Editor**。
   官方說明 v2 還需要 **BigQuery Read Session User**（Storage Read API）。下載 JSON key，
   **不要 commit 進 git**。
4. 註冊 dbt platform（Developer 方案）→ Account settings → New project → 選 BigQuery →
   上傳 JSON key。接著到 Your profile → Credentials，認證方式選 Service Account JSON，
   dataset 用預設值（慣例是 `dbt_<首字母><姓>`，開發時 model 會建在這裡），按 Test Connection。
   如果 build 時說沒有權限建立 dataset，就手動建同名 dataset，或幫 service account 加 BigQuery User 角色。
5. 連 GitHub：Account settings → Your profile → Linked accounts 連結 GitHub，安裝 dbt 的 GitHub App
   並授權這個 repo。dbt 專案就在 repo 根目錄，不需要設定子目錄。
6. 先把分支合併進 `main`，再開始在 Studio IDE 開發。

### 2. 在 Studio IDE 跑通

在 Studio IDE 的命令列依序執行（和本機 `make` 對應）：

```bash
dbt deps
dbt seed --full-refresh --vars '{"load_source_data": true}'
dbt build
```

實測結果：開發環境的 models 會建在你個人的 dataset（例如 `dbt_<名字>`，13 個物件，和 `prod` 相同），
seed 則固定寫入 `raw`。

載入資料後，記得依上游 README 的建議，刪掉 `seeds/jaffle-data`，或移除 `dbt_project.yml` 裡
`jaffle-data` 的設定，避免之後每次 seed 都重載。

### 3. 建 production environment 和 job

1. Deploy → Environments → **Create environment**，名稱 `Prod`，類型選 **Production**。
2. 填入 warehouse 憑證（正式環境建議用專用的 service account，學習時可先用自己的）。
3. **dbt 版本選 v2.0.0 以上**；Branch 設成 `main`，schema 設成 `prod`。
4. 在 `Prod` 裡 **Create job** → Deploy job，名稱 `Production Build`，指令用 `dbt build`。
5. 設定排程（建議先每天一次），按 **Run now** 手動跑一次，確認成功。

**Production job 不要帶 `--vars '{"load_source_data": true}'`。** `seeds/jaffle-data` 預設是停用的，
所以 `dbt build` 只重建 models 並跑 tests，`raw` 的原始資料保持原樣；帶了這個 var 才會用 seed 重載 `raw`。
本專案沒有 incremental model，所以每次 `dbt build` 都是整張重建（view 重新建立、table `CREATE OR REPLACE`）。

> 這就是「production job」的核心概念：job 永遠在 `main` 分支、建到 `prod` schema，開發時的實驗
> 只會進你自己的 dev schema，不會動到 production 的資料。

### 4. 體驗 CI（Developer 方案就有）

Developer 方案包含 GitHub 的 CI checks（定價頁的「Advanced CI」則不在 Developer 方案內）。
可以練習：開一個 PR 改 model，看平台的 CI job 在 PR 上的執行結果；搭配 GitHub 的 branch protection，
就能讓失敗的 CI 擋住合併。`.github/workflows/dbt-ci.yml` 是另一個**不依賴 dbt platform**
的版本：每次 push 都用 DuckDB 跑一遍 `make all`，可以拿來比較兩種 CI 的差別。

### 5. 試用 Semantic Layer（需要 Starter 或試用）

先做完 [02](02-metrics.md)，並且 Prod 環境至少成功跑過一次 job（官方要求）。官方文件的設定流程：

1. Account settings → Projects → 選專案 → Semantic Layer → **Configure Semantic Layer**，選擇 deployment environment。
2. 新增 Semantic Layer 的 warehouse 憑證（最小權限，只需讀取 metrics 所用的 schema），並建立 service token。
3. 用 token 從 BI 工具或 API 查詢 metrics。目前只支援查詢 deployment environment，開發環境「即將推出」。

在平台上連著專案時，metrics 指令改用 `dbt sl` 前綴（例如 `dbt sl list metrics`），
和本機的 `mf` 對應。
來源：[Administer the Semantic Layer](https://docs.getdbt.com/docs/use-dbt-semantic-layer/setup-sl)

## 看算出來的 metrics 與接 BI 工具

- **Metric 不是 BigQuery 裡的物件。** 定義在 `models/marts/*.yml`，編譯成 `target/semantic_manifest.json`；
  查詢時 MetricFlow 依定義即時產生 SQL 丟給 warehouse，結果不會寫回。BigQuery 裡只有底層的 marts table。
  本機可用 `mf query --explain` 看產生的 SQL，例如 `order_total` 會變成對 `prod.orders` 的
  `SUM(order_total) ... GROUP BY TIMESTAMP_TRUNC(ordered_at, month)`。
- **Studio IDE 的 `dbt sl query`：** 官方文件列為 Studio IDE 支援，但 Developer 方案能不能用，
  文件說法有出入，**沒有驗證**。
- **Developer 方案沒有 Semantic Layer API**，BI 工具不能直接用 metrics，只能連 `prod` 的 marts table
  （`orders`、`order_items`、`customers`、`products`、`locations`），在 BI 端自己寫聚合。

### Looker Studio（免費，已實測）

1. [lookerstudio.google.com](https://lookerstudio.google.com) → Create → Report → **BigQuery** 連接器，
   選 `<GCP project>` → `prod` → `orders`。
2. 時間序列：維度 `ordered_at`（年月），指標 `order_total`（Sum）。
3. 對數字：2024-09 的 `order_total` 應該是 **16,130.21**，與 `dbt sl query` / `mf query` 一致。

**踩坑：** 我們的資料只涵蓋 2024-09-01 到 2025-08-31。Looker Studio 的日期範圍預設為「自動」
（過去 28 天），會讓圖表只涵蓋到一部分資料，曾看到 651.86（剛好是 2024-09-30 單日的合計）而不是整月的 16,130.21。
日期範圍要手動設成自訂 `2024-09-01` ～ `2025-08-31`。換成「表格」維度 `ordered_at`（年月）會直接看到正確的 12 列。

## 檢查清單

- [x] Developer 帳號建立，warehouse 連線成功
- [x] Studio IDE 裡 `dbt build` 全部通過
- [x] `Prod` environment（v2.0.0+、`main`、`prod` schema）和 production job 成功執行過（Run now）
- [x] Looker Studio 連 `prod`，數字與 metric 一致
- [ ] 排程已設定，並在用量頁面確認沒有逼近 3,000 models
- [ ] （選做）Wizard 試用，或改用 BYOK
- [ ] （選做）Starter 試用：Semantic Layer 憑證、service token、從外部查詢 metrics

上一篇：[02 · Semantic layer 與 metrics](02-metrics.md)
