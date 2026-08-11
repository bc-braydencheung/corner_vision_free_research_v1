import 'package:flutter/material.dart';

import '../services/api_key_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = ApiKeyStore();
  final _rapidController = TextEditingController();
  final _visualCrossingController = TextEditingController();
  final _hkoController = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  @override
  void dispose() {
    _rapidController.dispose();
    _visualCrossingController.dispose();
    _hkoController.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    _rapidController.text = await _store.rapidApiKey;
    _visualCrossingController.text = await _store.visualCrossingKey;
    _hkoController.text = await _store.hkoWeatherKey;
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    await _store.setRapidApiKey(_rapidController.text);
    await _store.setVisualCrossingKey(_visualCrossingController.text);
    await _store.setHkoWeatherKey(_hkoController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('API 金鑰已儲存在本機')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          TextButton(onPressed: _save, child: const Text('儲存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.sports_soccer,
            title: '足球數據 API',
            subtitle: '選填 — 提供 API key 後可取得傷停、陣容等額外特徵',
          ),
          const SizedBox(height: 16),
          _ApiKeyTile(
            label: 'API-Football (RapidAPI)',
            controller: _rapidController,
            hint: '貼上 RapidAPI key',
            helpUrl: 'https://rapidapi.com/api-sports/api/api-football',
            helpText: '免費方案：每日 100 次請求。\n取得陣容、傷停、黃牌紅牌等數據。\n註冊 → 訂閱 API-Football → 複製 X-RapidAPI-Key。',
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            icon: Icons.cloud,
            title: '天氣數據 API',
            subtitle: '選填 — 提供 API key 後可取得歷史及預報天氣特徵',
          ),
          const SizedBox(height: 16),
          _ApiKeyTile(
            label: 'Visual Crossing',
            controller: _visualCrossingController,
            hint: '貼上 Visual Crossing API key',
            helpUrl: 'https://www.visualcrossing.com/weather-api',
            helpText: '免費方案：每日 1000 次請求。\n提供歷史風速、濕度、能見度等數據。\n註冊 → Account → API Key。',
          ),
          const SizedBox(height: 12),
          _ApiKeyTile(
            label: '香港天文台 (HKO)',
            controller: _hkoController,
            hint: '貼上 HKO API key（選填）',
            helpUrl: 'https://www.hko.gov.hk/tc/abouthko/opendata_intro.htm',
            helpText: '免費，需註冊。\n提供沙田/跑馬地鄰近氣象站即時天氣。\n用於賽前場地狀況預測。',
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            icon: Icons.info_outline,
            title: '無需 API Key 的數據來源',
            subtitle: '以下來源會自動啟用',
          ),
          const SizedBox(height: 16),
          _FreeSourceTile(
            icon: Icons.analytics,
            title: 'Understat xG',
            subtitle: '預期入球、射門位置數據（英超/西甲/德甲/意甲/法甲）',
          ),
          const SizedBox(height: 10),
          _FreeSourceTile(
            icon: Icons.bar_chart,
            title: 'FBref 球隊風格',
            subtitle: '傳中數、控球率、觸球區域比例等進階指標',
          ),
          const SizedBox(height: 10),
          _FreeSourceTile(
            icon: Icons.directions_run,
            title: '香港賽馬會試閘記錄',
            subtitle: '馬匹試閘時間、名次、晨操快操（現有爬蟲擴展）',
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF42E695)),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
        ),
      ],
    );
  }
}

class _ApiKeyTile extends StatefulWidget {
  const _ApiKeyTile({
    required this.label,
    required this.controller,
    required this.hint,
    required this.helpUrl,
    required this.helpText,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String helpUrl;
  final String helpText;

  @override
  State<_ApiKeyTile> createState() => _ApiKeyTileState();
}

class _ApiKeyTileState extends State<_ApiKeyTile> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF10251D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  onPressed: () => _showHelp(context),
                ),
              ],
            ),
            TextField(
              controller: widget.controller,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.controller.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '已設定 ✅',
                  style: const TextStyle(
                    color: Color(0xFF42E695),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('如何取得 ${widget.label}'),
        content: Text(widget.helpText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}

class _FreeSourceTile extends StatelessWidget {
  const _FreeSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF10251D),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF42E695)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
        ),
        trailing: const Icon(Icons.check_circle, color: Color(0xFF42E695)),
      ),
    );
  }
}
