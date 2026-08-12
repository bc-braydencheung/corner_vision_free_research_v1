import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/marksix_mobile.dart';

/// Full-screen WebView that loads HKJC Mark Six results page.
/// User sees the real page, taps "Import" to extract draw data from DOM.
class MarkSixImportScreen extends StatefulWidget {
  const MarkSixImportScreen({super.key});
  @override
  State<MarkSixImportScreen> createState() => _MarkSixImportScreenState();
}

class _MarkSixImportScreenState extends State<MarkSixImportScreen> {
  late final WebViewController _controller;
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(
          'https://bet.hkjc.com/ch/marksix/results'));
  }

  Future<void> _extractData() async {
    setState(() => _extracting = true);
    try {
      // Click "past results"
      await _controller.runJavaScript('''
        (function(){
          var all=document.querySelectorAll('a,button,[role=tab]');
          for(var e of all){
            var t=e.innerText||e.textContent||'';
            if(t.indexOf('過去')>=0||t.indexOf('Past')>=0){e.click();return'ok';}
          }
          return'not found';
        })();
      ''');
      await Future.delayed(const Duration(seconds: 4));

      // Extract
      final result = await _controller.runJavaScriptReturningResult('''
        (function(){
          var draws=[],seen={};
          document.querySelectorAll('table tr,[class*=result],[class*=draw],[class*=row]').forEach(function(e){
            var t=(e.innerText||e.textContent||'').trim();
            var m=t.match(/(\\d{2,4}\\/\\d{3,4})/);
            if(m&&!seen[m[1]]){seen[m[1]]=1;draws.push(t);}
          });
          return JSON.stringify(draws);
        })();
      ''');

      if (result is String) {
        final list = json.decode(result) as List;
        final draws = <MarkSixDraw>[];
        for (final block in list.cast<String>()) {
          final dm = RegExp(r'(\d{2,4}/\d{3,4})').firstMatch(block);
          if (dm == null) continue;
          final dt = RegExp(r'(\d{4}[-/]\d{1,2}[-/]\d{1,2})').firstMatch(block);
          final nums = <int>{};
          for (final m in RegExp(r'\b([1-9]|[1-4]\d|49)\b').allMatches(block)) {
            final n = int.parse(m.group(1)!);
            if (1 <= n && n <= 49) nums.add(n);
          }
          if (nums.length < 6) continue;
          final sn = nums.toList()..sort();
          draws.add(MarkSixDraw(
            drawNumber: dm.group(1)!,
            drawDate: dt?.group(1) ?? '',
            numbers: sn.sublist(0, 6),
            specialNumber: sn.length > 6 ? sn[6] : 0,
            source: 'webview-import',
          ));
        }
        if (draws.isNotEmpty && mounted) {
          Navigator.pop(context, draws);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到數據，請確保已顯示攪珠結果')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提取失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('從 HKJC 匯入六合彩數據'),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          color: Colors.black87,
          child: const Text(
            '1. 點擊「過去攪珠結果」\n2. 看到號碼後點下方「匯入」',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _extracting ? null : _extractData,
        icon: _extracting
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download),
        label: Text(_extracting ? '提取中...' : '匯入數據'),
      ),
    );
  }
}
