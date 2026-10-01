# 03 · dbt platform：Studio IDE、AI、部署與 production job

> **驗證狀態：** 01、02 篇的指令都在本機實測過。這一篇需要你自己的 dbt platform 帳號和雲端 warehouse，
> 我沒辦法代為執行，步驟來自官方文件和 jaffle-shop 上游 README（2026-10 查閱），
> 實際畫面可能有出入，以官方文件為準。

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
   和 production job 時，要準備其中一種雲端 warehouse。
   （[About connections](https://docs.getdbt.com/docs/cloud/connect-data-platform/about-connections)、
   [Supported data platforms](https://docs.getdbt.com/docs/supported-data-platforms)）
2. **Environment 的 dbt 版本要選 v2.0.0 以上。** 本專案的 `dbt_project.yml` 有
   `require-dbt-version: ">=2.0.0"`，選到 v1.x 會在版本檢查時失敗。
3. **本機的 `profiles.yml` 在平台上沒有作用**，平台使用你在 Account settings → Connections 設定的連線。

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

### 1. 準備 warehouse 和帳號

1. 在你的 warehouse 建一個空的資料庫／專案給 jaffle-shop 用，並備好有建立 schema 和資料表權限的帳號。
2. 註冊 dbt platform（Developer 方案），建立專案，依[各 warehouse 的 Quickstart](https://docs.getdbt.com/guides)
   設定 connection。
3. 把你的 GitHub repo（也就是這個 repo）連到專案。dbt 專案就在 repo 根目錄，不需要設定子目錄。

### 2. 在 Studio IDE 跑通

在 Studio IDE 的命令列依序執行（和本機 `make` 對應）：

```bash
dbt deps
dbt seed --full-refresh --vars '{"load_source_data": true}'
dbt build
```

載入資料後，記得依上游 README 的建議，刪掉 `seeds/jaffle-data`，或移除 `dbt_project.yml` 裡
`jaffle-data` 的設定，避免之後每次 seed 都重載。

### 3. 建 production environment 和 job

1. Deploy → Environments → **Create environment**，名稱 `Prod`，類型選 **Production**。
2. 填入 warehouse 憑證（正式環境建議用專用的 service account，學習時可先用自己的）。
3. **dbt 版本選 v2.0.0 以上**；Branch 設成 `main`，schema 設成 `prod`。
4. 在 `Prod` 裡 **Create job** → Deploy job，名稱 `Production Build`，指令用 `dbt build`。
5. 設定排程（建議先每天一次），按 **Run now** 手動跑一次，確認成功。

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

## 檢查清單

- [ ] Developer 帳號建立，warehouse 連線成功
- [ ] Studio IDE 裡 `dbt build` 全部通過
- [ ] `Prod` environment（v2.0.0+、`main`、`prod` schema）和 `Production Build` job 成功執行過
- [ ] 排程已設定，並在用量頁面確認沒有逼近 3,000 models
- [ ] （選做）Wizard 試用，或改用 BYOK
- [ ] （選做）Starter 試用：Semantic Layer 憑證、service token、從外部查詢 metrics

上一篇：[02 · Semantic layer 與 metrics](02-metrics.md)
