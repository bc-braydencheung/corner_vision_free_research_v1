/// Auditable description of one model shipped in the app.
///
/// The cards are deliberately part of the app rather than of the repository
/// documentation: a research tool that shows probabilities has to state, on the
/// same device, what produced them, which free data they rest on, what gate
/// they had to pass and where they are known to be weak.
class ModelCard {
  const ModelCard({
    required this.name,
    required this.purpose,
    required this.data,
    required this.method,
    required this.gate,
    required this.limits,
  });

  final String name;
  final String purpose;

  /// Free sources the model is trained or conditioned on.
  final String data;
  final String method;

  /// What has to hold before the model is allowed to be shown or traded.
  final String gate;

  /// Known failure modes, stated plainly.
  final String limits;
}

/// Cards for every model the app actually runs.
const modelCards = <ModelCard>[
  ModelCard(
    name: '角球 NB2 市場模型',
    purpose: '由馬會全部角球大細盤聯合擬合一個總角球期望值，再算每盤機率與期望值。',
    data: '馬會公開角球盤與賠率（CHL）、football-data.co.uk 免費歷史角球。',
    method:
        '負二項（NB2）計數分布，過度分散由該聯賽自身殘差估計；'
        '各盤以隱含機率去水後聯合擬合，並與隊伍評分先驗在對數空間按不確定度混合。',
    gate: '未通過 Brier 技巧審核前，信心上限鎖 0.39；線上偵測到漂移時上限 0.30。',
    limits:
        '角球結算規則差異（例如加時、比賽中斷）不在模型內；'
        '盤口極少或只有單一盤時，市場約束不足，模型與市場的差距不可信。',
  ),
  ModelCard(
    name: '角球隊伍評分（時變 Kalman）',
    purpose: '為每場提供市場以外的獨立角球期望值先驗。',
    data: 'football-data.co.uk 免費歷史賽果（主客角球數）。',
    method:
        '層級對數狀態（攻/守）＋每場一次擴展 Kalman 更新，'
        '場間以 Ornstein-Uhlenbeck 回歸聯賽平均，久未出賽的隊伍評分自動衰減。',
    gate: '樣本少於 6 場或對數方差 ≥0.05 的先驗不參與混合。',
    limits: '無陣容、傷停、賽程密度資料；升班／降班隊伍跨聯賽資訊有限。',
  ),
  ModelCard(
    name: '角球兩層模型（射門 × 轉化 × 裁判）',
    purpose: '把角球拆成「射門量」與「射門轉角球率」兩層，並讓裁判在其物理位置進入模型。',
    data: 'football-data.co.uk 免費歷史射門（HS/AS）、角球（HC/AC）及裁判欄（Referee）。',
    method:
        '指數加權對數狀態估計射門攻守與轉化率；'
        '裁判以該場總角球對聯賽平均的對數比收縮估計，'
        '最後與 Kalman 先驗以逆方差在對數空間合併。',
    gate: '裁判樣本少於 12 場不影響期望值；隊伍樣本以 8 場為半數可信度收縮。',
    limits:
        '免費歷史無 xG（已再次驗證：FBref 回 403、Understat 聯賽與球隊頁已不再內嵌'
        '賽事資料，只有逐場頁有 xG 而無法由免費頁列舉），'
        '故射門質量只以「射正 0.32／射失 0.09」加權成代理欄，'
        '屬粗代理而非官方 xG；'
        '馬會免費賽程與 GraphQL 均無賽前裁判欄（已驗證：schema introspection 被拒、'
        '賽前預測內文亦無標註球證），故裁判項只在賽後歷史中生效，賽前為中性；'
        '裁判效應與其常帶的球隊組合混淆，不可解讀為因果。',
  ),
  ModelCard(
    name: '賽前軍情（停賽／上陣成疑／傷缺）',
    purpose: '把免費公開的缺陣人數轉成不確定度，而非方向性預測。',
    data: '馬會足球資訊網賽前預測內的標註欄（停賽、上陣成疑、受傷／缺陣）。',
    method:
        '只解析標註欄，不從內文散文推斷傷情；'
        '缺陣人數（成疑計半人）只放寬 NB2 過度分散，上限 0.02，永不移動平均值。',
    gate: '無公開軍情或欄位為「／」時為中性；隊名以馬會中文名對接賽程。',
    limits:
        '馬會明示該內容由第三方提供且未經核實，故一律標記為未核實；'
        '無首發名單、無出場時間，缺陣對角球的方向性影響未經回測證實；'
        '已驗證並無可用的免費賽前首發來源（SofaScore 回 403、'
        'football-data.org 免費層拒絕存取、openfootball 只有賽程與比分、'
        'Wikipedia 無結構化首發），故不會把未核實軍情當方向性訊號；'
        '每次捕取改為附時間追加保存（不覆寫舊紀錄），'
        '待累積足夠捕取紀錄才有可能回測方向性。',
  ),
  ModelCard(
    name: '市場偏離模型（residual）',
    purpose: '直接學「馬會盤口幾時錯」，而不是獨立預測角球數後才與盤口比較。',
    data: '本機影子預測紀錄：捕取當時的馬會去水公平機率、模型機率與實際賽果。',
    method:
        '以去水後的公平機率作對數勝算基底（offset），'
        '只用「模型與盤口的對數勝算分歧」作唯一特徵（上下限 ±2），'
        '以 L2 ridge 擬合常數與分歧權重。',
    gate:
        '樣本少於 60 筆不擬合；按時間切分後 30% 作 holdout；'
        '只有 holdout 的 Brier 與 log loss 同時勝過純盤口才啟用，'
        '否則直接返回盤口機率，完全不移動顯示的機率。',
    limits:
        '只使用捕取當時的盤口（絕不用收盤價作賽前特徵）；'
        '樣本仍在累積，未通過閘門時即等於未啟用；'
        '單一分歧特徵無法分辨盤口為何錯。',
  ),
  ModelCard(
    name: '角球主客聯合分布（協方差）',
    purpose: '用量測到的主客角球協方差取代「主客獨立」假設。',
    data: 'football-data.co.uk 免費歷史主客角球（HC/AC）。',
    method:
        '逐聯賽估主客角球方差與協方差，得總數方差；'
        '若總數方差超過泊松，超出部分換算成 NB2 過度分散。',
    gate: '該聯賽少於 200 場不採用；總數方差窄於泊松時不收窄分布。',
    limits:
        '相關性符號由資料決定，並未假定負相關；'
        '只放寬分布寬度，未證實可改善預測前不移動平均值。',
  ),
  ModelCard(
    name: '賽馬條件 logit + Harville/Henery',
    purpose: '由免費排位與賽果推出每匹馬的勝／位置機率。',
    data: '馬會公開排位、賽果、獨贏／位置投注池，Open-Meteo 及香港天文台免費天氣。',
    method:
        '條件 logit（softmax over 同場馬匹）；位置機率用 Harville/Henery；'
        '投注池先驗與模型在對數空間混合，並作冷門偏差（favourite-longshot）修正。',
    gate: '模型與投注池差距受不確定度限制；資料缺失的場次不予顯示推介。',
    limits:
        '無騎練師配合度、無沙圈觀察、無詳細傷病資料；'
        '步速與檔位情境由免費資料粗略推斷，雨後場地變化只增加不確定度。',
  ),
  ModelCard(
    name: '線上學習（Hedge + 漂移偵測）',
    purpose: '按已結算結果調整模型相對市場的信任度，並在漂移時自動回滾。',
    data: '本機影子預測與已結算賽果。',
    method:
        'Brier 損失下的指數加權（Hedge）模型組合，權重下限 0.03；'
        'Page-Hinkley 與 CUSUM 雙偵測器；市場移動與模型漂移分開歸類；'
        '漂移警報觸發回滾至上一個檢查點。',
    gate: '少於 30 個已結算樣本時不改動任何顯示；無效／取消／缺資料的事件不更新模型。',
    limits:
        '結算樣本增長慢，短期權重變化的統計意義有限；'
        '若市場本身系統性改變，回滾只能延緩而不能修正模型結構。',
  ),
  ModelCard(
    name: '校準層（溫度／等距回歸）',
    purpose: '讓顯示的機率與實際頻率對應，而不是只反映模型分數。',
    data: '本機已結算樣本。',
    method:
        '<50 樣本不校準；<200 用溫度縮放；≥200 用等距回歸；'
        '以 Brier 技巧分數對比基準（市場價）審核。',
    gate: '未勝過基準前不顯示「高」信心。',
    limits: '校準只修正平均對應關係，不能修正模型缺失的變數。',
  ),
  ModelCard(
    name: 'Purged walk-forward 驗證',
    purpose: '在時間順序下重複驗證，避免單一 holdout 的樂觀偏差。',
    data: '訓練資料集本身（football-data 免費歷史）。',
    method:
        '擴張訓練窗；每折之間 purge 特徵重疊期並加 temporal embargo；'
        '逐折計 MAE 與 Brier，並與基準比較。',
    gate: '折數 ≥3、過半數折勝基準且整體 MAE/Brier 勝基準，模型才可放行。',
    limits:
        '免費歷史的比賽數有限，折數多時每折樣本變薄；'
        '球隊名稱跨季變動可能影響長窗一致性。',
  ),
];
