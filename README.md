# EdgeWise（睿測）

以免費 [Football-Data.co.uk](https://www.football-data.co.uk/data.php) CSV 建立的多聯賽角球機率分析及虛擬模擬 App。

## 已支援

- 英超 `E0`＋英冠 `E1` 升班先驗；
- 西甲 `SP1`＋西乙 `SP2`；
- 法甲 `F1`＋法乙 `F2`；
- 德甲 `D1`＋德乙 `D2`；
- 意甲 `I1`＋意乙 `I2`；
- 足球／香港賽馬切換介面；
- 香港賽馬會公開排位及賽果頁的低頻率、本機快取個人研究爬蟲；
- 香港賽馬無洩漏日期切分、動態往績／排名提升候選、獨贏及位置機率；
- 香港賽馬自訂獨贏賠率 EV、保守 EV、模擬買入及賽果結算；
- 自訂大／小角球盤、十進制賠率及虛擬注碼；
- 整數、半球及 0.25／0.75 亞洲盤 EV；
- 只在保守 EV 為正、資料及信心達標時允許模擬買入；
- 本機持久化模擬戶口、自動結算、ROI 及最大回撤；
- App 直接增量檢查五大聯賽及次級聯賽 CSV，原子保存最新正式賽果及賽程；
- 足球新增賽果後可在手機全量訓練五個獨立純 Dart count challenger；
- App 先顯示本機賽馬快取，再低頻檢查 upcoming 排位及新增賽果；
- 排位按永久馬匹 ID 合併中英文馬名，同日退馬、檔位及騎練變更會改變內容 hash；
- 香港賽馬新增賽果後可在手機全量訓練純 Dart ranking challenger；
- 足球及賽馬的 Android／iOS 訓練進度、資料版本及每五個 epoch checkpoint 會持久保存；
- 候選模型通過 validation／holdout 後才原子啟用，失敗時沿用舊模型；
- App 啟動時比較遠端 `dataVersion`，失敗時安全使用內置資料。

J1 及澳職不在目前範圍。香港賽馬模組只供個人非商業研究：不繞過登入或存取控制，不高頻抓取，不在 payload 內公開原始網頁或完整資料庫；網站條款或頁面結構改變時應停用並重新核對。

「全球最準」及穩定回報均不能被保證。本專案以無資料洩漏、候選外評估、機率校準及不可修改的未來模擬記錄作為可驗證目標。

## 模型流程

```text
五個頂級聯賽＋各自次級聯賽 CSV
    ↓
按聯賽清洗、日期排序、升班資料折算
    ↓
動態球隊角球攻守、主客場、射門、休息日、Elo及市場特徵
    ↓
較早 development folds 選擇 dynamic／Poisson／boosting／residual／ensemble
    ↓
最新兩季 candidate holdout 評分
    ↓
每個聯賽獨立分散度、機率校準及80%區間
    ↓
0–30+總角球連貫機率分布
    ↓
assets/data/latest.json → Flutter App
```

同一場比賽的 `HC`、`AC`、`HS`、`HST` 等賽後數據不會進入該場特徵。相同日期的所有賽事會先產生特徵，再更新球隊狀態，避免同日早場結果洩漏。各聯賽分開訓練及校準，不會把不同聯賽節奏直接混成單一模型。

### 足球市場及賽前天氣研究資料

**新增數據源（2026 更新）：**

- **Understat xG**：預期入球、射門位置（英超/西甲/德甲/意甲/法甲），免費，自動快取，無需 API key
- **FBref**：傳中、控球率、觸球區域等球隊風格指標，免費，自動快取，無需 API key
- **API-Football**：傷停、陣容（需 RapidAPI 免費層級 key，每日 100 次請求），在 App「設定」頁貼上 key 即可
- **Visual Crossing**：歷史風速/濕度（需免費 API key），在 App「設定」頁貼上 key 即可
- **HKO 天氣**：香港天文台即時天氣，用於賽前場地狀況預測（需免費 API key）

以上數據源均為選填；沒有 API key 時自動降級使用現有功能，不影響正常運作。

所有 API 金鑰只儲存在手機本機，不會上傳至任何伺服器。

```bash
# 完整管線（含所有免費來源）：
python -m forecasting \
  --output assets/data/latest.json \
  --cache-dir data/raw \
  --understat-cache data/understat \
  --fbref-cache data/fbref \
  --api-football-key YOUR_RAPIDAPI_KEY \
  --visual-crossing-key YOUR_VC_KEY
```

### 足球市場及賽前天氣研究資料

Football-Data 的入球市場賠率不可當成角球賠率。角球市場 challenger 只接受帶時間戳的真實大／小角球盤，先移除兩邊 overround，再把 count model 收縮至市場機率；分層校準、保守機率、研究限價及 match-day bootstrap 全部通過前，App 保持市場交易閘門停用。

Betfair Historical Data Basic 是免費的一分鐘最後成交價資料，但需由使用者以自己的 Betfair 帳戶在 <https://historicdata.betfair.com/> 下載。解壓 TAR 後可直接匯入 `.bz2`：

```bash
python -m forecasting.betfair_historical \
  data/betfair/BASIC \
  --football-data data/raw \
  --output data/football/corner_market_snapshots.csv
python -m forecasting \
  --output assets/data/latest.json \
  --cache-dir data/raw \
  --market-data data/football/corner_market_snapshots.csv
```

匯入器只保存開賽前、同時有 Over／Under 價格的角球盤，保留 market ID、事件原名、盤口、market time、`captured_at` 及來源。沒有下載檔案便沒有歷史市場資料；不會用最終價、固定 9.5／1.90 或入球盤價補造 T-60／T-10 快照。

Open-Meteo helper 只擷取當刻可見的未來天氣預報並保存 `captured_at` 及預報有效時間，不會以賽後再分析天氣倒灌入早段預測。球場沒有可靠座標時保持缺失，不猜測天氣。Open-Meteo 資料須按其條款標示來源（CC BY 4.0）；商業用途須另行核對方案。

目前不使用 API-Football。陣容及傷停在沒有另一個穩定、合法及帶時間戳的免費來源時標示為 unavailable；「沒有資料」不等於「沒有傷停」。

## EV

半球盤：

```text
EV = 勝出機率 × (賠率 - 1) - 落敗機率
```

整數盤加入退回本金機率；四分之一盤會平均拆成相鄰整數／半球盤，例如大 10.25 等於一半大 10.0、一半大 10.5。App 同時顯示點估計 EV 及扣除模型不確定性的保守 EV，只有後者為正才可加入模擬戶口。

所有「買入」均為虛擬記錄，不涉及支付、存款、提款或博彩公司。開賽前建立的記錄不能修改；模型版本、盤口、賠率、機率及時間均會保存，避免事後挑選。
虛擬戶口提供固定 0.25% 及十分一 Kelly 低風險模式；單項上限為戶口
0.5%、每個賽事日總曝險上限 2%，最大回撤達 15% 便停止新增記錄。
注碼限制只控制風險，不會令負期望值策略變成正期望值。

## 本機產生預測

需要 Python 3.10+：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install .
python -m forecasting --output assets/data/latest.json --cache-dir data/raw
python -m unittest discover -s tests -v
```

沒有 `HC/AC` 的舊球季會被忽略，不會當作零。次級聯賽只建立升班先驗，不會成為頂級聯賽 target。

### 足球手機更新及重訓

`football_mobile_seed.json.gz` 包含五大聯賽及各自次級聯賽的已清洗歷史賽果、角球、射門、入球及可用賽前市場欄位。App 啟動時先載入 active 快照，再由最後完整賽果所屬球季起增量檢查 Football-Data CSV；未來賽程另由 `fixtures.csv` 更新。新資料完整解析、去重及驗證後才原子替換 active dataset，失敗時保留舊資料及預測。

手機端為每個頂級聯賽建立獨立的 recency-weighted log-count challenger，按日期以 70%／15%／15% 分成 development、validation 及最後 holdout，分別預測主隊、客隊及總角球，再產生 0–30+ 連貫機率分布。只有 challenger 的總角球 MAE 及大 9.5 Brier 在 validation／holdout 均不差於動態基準時才啟用；否則該聯賽保留 mobile dynamic baseline。中央 Python champion／challenger 管線仍可透過遠端 JSON 提供更完整的模型競賽及校準。

新足球賽果出現時，App 顯示「重新訓練五大聯賽模型」。訓練使用固定資料快照，每五個 epoch、每個資料切分階段及每個聯賽保存 checkpoint；重新開 App 可繼續或以最新資料重開。新資料在訓練期間到達時，舊快照可以完成但不會啟用。

### 香港賽馬個人研究資料

首次建立歷史快取（請勿縮短成高頻率大量請求）：

```bash
python -m forecasting.racing \
  --start-date 2021-09-01 \
  --cache-dir data/racing \
  --output data/racing/latest.json \
  --interval 0.75
python -m forecasting --output assets/data/latest.json --cache-dir data/raw
```

爬蟲會先快取每個賽馬日及各場賽果頁，只抓取未處理日期；它會檢查所有日曆日以涵蓋週末及公眾假期賽事，排位頁只在產生預測時更新。歷史特徵只使用當場之前的馬匹、騎師及練馬師往績、近況、路程、負磅、檔位、場地及班次。約 70%／15%／15% 賽事按日期分為 development、候選選擇及最後 holdout；獨贏機率在同場正規化至 100%，位置機率按位置名額聯合校正。

App 內置的 `racing_mobile_seed.json.gz` 覆蓋 2021/22 至 2025/26 五個馬季，只包含重訓所需的數值特徵、標籤及聚合往績狀態，不包含原始 HTML 或完整歷史 CSV。啟動時先讀取 active 快照；排位使用六小時條件快取，到期或手動更新時才低頻下載 HKJC 英文及中文頁，並以日期及內容 hash 判斷是否真的改變。新賽果會先寫入 staging、重新解析及驗證，成功後才原子替換 active dataset。

手機訓練器是可序列化的 logistic ranking challenger，不是假裝在 Flutter 內執行 scikit-learn `HistGradientBoosting`。它會按賽事日期建立 development／validation／holdout，分別訓練獨贏及位置模型，同場機率再作總和約束。若 challenger 未勝過動態往績基準，訓練仍會完成，但 active 預測保留基準。

訓練開始後每五個 epoch 及每個日期切分階段保存 checkpoint。重新開 App 時可選擇「繼續上次訓練」或「以最新資料重開」；舊 active model 在候選完成前一直可用。Android 使用 WorkManager 並優先要求充電及非計量網絡，嘗試在 App 離開或鎖屏後續跑；iOS 使用 `BGProcessingTask`，實際執行時間由系統決定。兩個平台均可由 checkpoint 恢復，但不能保證被強制停止、iOS 強制關閉或極端省電限制後仍立即完成。

### 研究健康、shadow及復原

「研究健康」頁集中顯示 Football-Data、Betfair Basic、Open-Meteo 及
HKJC 的快取／錯誤狀態、資料覆蓋、最後快照時間、歷史漂移及前瞻
shadow MAE／Brier。未有真實角球價格時，交易閘門維持停用，不會以
最終價格或固定 1.90 冒充市場資料。未來預測首次出現時會保存不可修改
shadow 記錄，至少結算 30 場後才判斷穩定、監察或停止；嚴重漂移會停止
新增足球模擬記錄。

研究頁可把模擬記錄、市場／天氣快照、shadow 記錄及研究報告複製為本機
JSON 備份。匯入時會驗證 schema、checksum、重複 ID、時間關係及不可修改
記錄；研究報告包含逐注、分季／策略ROI、校準分箱、最大回撤、90%／95%
meeting bootstrap 區間及資料限制。大型可重建訓練資料及原始受限制網頁不會放入
剪貼簿備份或 APK。

賠率由用戶自行輸入，App 不把最終賠率當作較早預測特徵。獨贏及位置市場均使用同一簡化 EV：

```text
EV = 模型市場機率 × 十進制賠率 - 1
```

位置結算按 App 保存的當場馬匹數使用兩個或三個位置名額；若日後接入正式彩池規則或特殊賽事，必須先更新結算規則。所有用戶輸入賠率均保存建立時間，不會用作事後改寫預測。

香港賽馬會資料的自動存取、衍生使用及再發布權利並未由本專案保證。這個模式只適合使用者自己的研究裝置及私有快取；不要把 `data/racing/`、原始 HTML 或歷史 CSV 提交到公開 repository。

## Flutter

需要 Flutter 3.44.6+：

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

未設定遠端 URL 時，足球先使用內置 Python 模型快照，並可在個人裝置增量更新賽果／賽程及訓練 mobile challenger；香港賽馬亦可低頻檢查排位及賽果。要額外啟用免費中央 Python 完整模型更新，可設定 repository 的 GitHub Pages：

```bash
flutter run \
  --dart-define=FORECAST_DATA_URL=https://OWNER.github.io/REPOSITORY/latest.json
```

Android 打包：

```bash
flutter build apk --release \
  --dart-define=FORECAST_DATA_URL=https://OWNER.github.io/REPOSITORY/latest.json
```

`.github/workflows/refresh-data.yml` 會按 Football-Data 的更新節奏重新下載、訓練及發布 JSON，並使用 Actions cache。手機不會嵌入 Python 或 scikit-learn；足球及香港賽馬均使用可序列化的純 Dart challenger，而較完整的 Python 特徵重建、模型競賽和校準仍可由中央排程執行。

基於個人研究及來源條款限制，預設 GitHub Pages workflow **不會**替使用者抓取香港賽馬會。手機 HKJC 存取只適合使用者自己的低頻單機快取；未經適當權利確認，不應把相關原始資料、完整歷史資料庫或自動爬蟲服務公開部署。

## 評估

每個聯賽獨立報告：

- `maeTotalCorners`：最新兩個 candidate holdout 球季的總角球 MAE；
- `baselineMaeHoldout`：動態分層基準在相同場次的 MAE；
- `maeSkillVsDynamicPercent`：相對動態基準改善；
- `withinTwoHoldout`：誤差在 ±2 角球內的比例；
- `brierOver8_5/9_5/10_5`：大小機率誤差；
- `brierSkillOver*Percent`：相對歷史發生率的改善；
- `calibrationErrorOver*`：機率與實際頻率的差距；
- `validationMatches`：步進評估場數。

模型健康度不等於勝率。卡片信心會綜合資料完整度、升班先驗比例、預測區間、歷史校準、球隊經驗及方向清晰度。真正不可污染的證據仍必須來自發布後的未來模擬結果。

香港賽馬另按完整賽事日期分成 development、validation 及最後 holdout：

- `winLogLoss`／`baselineWinLogLoss`：勝馬機率對數損失及動態往績基準；
- `winBrier`：獨贏機率 Brier Score；
- `placeBrier`／`baselinePlaceBrier`：位置機率及基準 Brier Score；
- 只有 validation 選中的提升模型在最後 holdout 仍勝過基準時才部署，否則保留動態往績基準；
- 同場獨贏機率總和約為 100%，位置機率總和按該場位置名額校正。

這些指標只反映所抓取歷史資料上的時間留出表現，不代表盈利能力，也不能取代真正發布後、不可修改的未來預測記錄。

## 資料及責任

Football-Data 表示主要歐洲聯賽提供歷史角球等比賽統計，但欄位及覆蓋會隨年份改變。香港賽馬資料來自使用者指定的香港賽馬會公開頁面，只以低頻率及本機快取作個人研究。商業發布、公開 API、公開資料集或重新發布前，必須先取得適當權利並重新確認所有來源的最新條款。

本 App 只供統計研究及虛擬模擬，不構成財務或投注建議。預測及 EV 均可能錯誤，任何結果不獲保證。
