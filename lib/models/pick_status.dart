/// How much proof stands behind a pick, which is not how strong it looks.
///
/// Every fixture and every race now names a first choice, so the only honest
/// way to keep a weak pick apart from a proven one is to say which of the two
/// it is on the pick itself. A high model probability never promotes a pick:
/// only settled samples where the model beat the market do.
enum PickStatus {
  /// The model beat the market on settled samples and this pick clears the
  /// edge threshold.
  verified,

  /// The model's own first choice, with no proven market edge behind it.
  unverified,

  /// Not enough usable data to judge the pick at all.
  insufficient;

  String get label => switch (this) {
    PickStatus.verified => '已驗證',
    PickStatus.unverified => '未驗證',
    PickStatus.insufficient => '資料不足',
  };

  /// One line stating what the status does and does not claim.
  String get note => switch (this) {
    PickStatus.verified => '模型在已結算樣本上勝過市場，且這注過門檻。',
    PickStatus.unverified => '模型首選，但未有證據勝過市場，只作研究參考。',
    PickStatus.insufficient => '資料不足以評估，只顯示模型偏好。',
  };

  /// Whether the record may count this pick as a model recommendation.
  bool get proven => this == PickStatus.verified;
}
