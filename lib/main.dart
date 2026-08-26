// ============================================================
// 瞬译 - 液态玻璃风格 + 语音功能
// ============================================================
// 依赖（pubspec.yaml）：
//   dependencies:
//     flutter:
//       sdk: flutter
//     http: ^1.2.0
//     speech_to_text: ^6.6.0      # 语音识别
//     flutter_tts: ^4.0.2          # 语音合成
//
// Android 权限（android/app/src/main/AndroidManifest.xml）：
//   <uses-permission android:name="android.permission.RECORD_AUDIO"/>
//   <uses-permission android:name="android.permission.INTERNET"/>
//   <uses-permission android:name="android.permission.BLUETOOTH"/>
//   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
//
// iOS 权限（ios/Runner/Info.plist）：
//   <key>NSSpeechRecognitionUsageDescription</key>
//   <string>需要语音识别权限以支持语音输入</string>
//   <key>NSMicrophoneUsageDescription</key>
//   <string>需要麦克风权限以支持语音输入</string>
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'subscription_service.dart';
import 'paywall.dart';
import 'redeem_screen.dart';
import 'seller_confirm.dart';
import 'payment/payment_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:archive/archive.dart';

void main() {
  // 把 Dart 异常显示到屏幕上,方便排查 iOS 27 上的白屏(而不是静默白屏)
  ErrorWidget.builder = (details) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F7FA),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️ 渲染出错',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  details.exceptionAsString(),
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      debugPrint('⚠️ Uncaught error: $error');
      debugPrint(stack.toString());
    },
  );
}

// ============================================================
// 液态玻璃按钮 - 通用组件
// ============================================================
class LiquidGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool isPrimary; // 主按钮（带渐变色）
  final Color? accentColor; // 主按钮的强调色
  final double blurSigma;

  const LiquidGlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.isPrimary = false,
    this.accentColor,
    this.blurSigma = 16,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _disabled => widget.onPressed == null;

  void _onTapDown(TapDownDetails _) {
    if (_disabled) return;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? const Color(0xFF5D6CFF);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _disabled ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          );
        },
        child: Opacity(
          opacity: _disabled ? 0.5 : 1.0,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                // 玻璃质感渐变
                gradient: widget.isPrimary
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                              Colors.white.withOpacity(0.35), accent),
                          accent,
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(_disabled ? 0.4 : 0.78),
                          Colors.white.withOpacity(_disabled ? 0.25 : 0.48),
                        ],
                      ),
                border: Border.all(
                  color: Colors.white.withOpacity(_disabled ? 0.3 : 0.65),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.isPrimary
                        ? accent.withOpacity(0.45)
                        : Colors.black.withOpacity(0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                    spreadRadius: widget.isPrimary ? 1 : 0,
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.55),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // 内容
                  Center(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: widget.isPrimary
                            ? Colors.white
                            : const Color(0xFF4E5875),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      child: IconTheme.merge(
                        data: IconThemeData(
                          color: widget.isPrimary
                              ? Colors.white
                              : const Color(0xFF5F6A85),
                        ),
                        child: widget.child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 液态玻璃圆形图标按钮
// ============================================================
class LiquidGlassCircleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double size;
  final Color? accentColor;
  final bool isActive; // 激活状态（如正在录音/播放）

  const LiquidGlassCircleButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.size = 48,
    this.accentColor,
    this.isActive = false,
  });

  @override
  State<LiquidGlassCircleButton> createState() =>
      _LiquidGlassCircleButtonState();
}

class _LiquidGlassCircleButtonState extends State<LiquidGlassCircleButton>
    with TickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isActive) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LiquidGlassCircleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _disabled => widget.onPressed == null;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? const Color(0xFF5D6CFF);

    return GestureDetector(
      onTapDown: (_) {
        if (!_disabled) _pressController.forward();
      },
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: _disabled ? null : widget.onPressed,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 脉冲光晕（激活时）
            if (widget.isActive)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) {
                  return Container(
                    width: widget.size * _pulseAnim.value,
                    height: widget.size * _pulseAnim.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.25),
                    ),
                  );
                },
              ),
            // 按钮主体
            AnimatedBuilder(
              animation: _scaleAnim,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnim.value,
                  child: child,
                );
              },
              child: ClipOval(
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.isActive
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(
                                  Colors.white.withOpacity(0.3), accent),
                              accent,
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.75),
                              Colors.white.withOpacity(0.45),
                            ],
                          ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isActive
                            ? accent.withOpacity(0.4)
                            : Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 顶部高光弧
                      Positioned(
                        top: 2,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: widget.size * 0.35,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.5),
                                Colors.white.withOpacity(0),
                              ],
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(widget.size),
                            ),
                          ),
                        ),
                      ),
                      IconTheme.merge(
                        data: IconThemeData(
                          color: widget.isActive
                              ? Colors.white
                              : const Color(0xFF5F6A85),
                          size: widget.size * 0.42,
                        ),
                        child: widget.child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 主应用
// ============================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lingua link',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F6F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 101, 115, 241),
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: const Color(0xFF202536),
              displayColor: const Color.fromARGB(255, 40, 48, 73),
            ),
        useMaterial3: true,
      ),
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============================================================
// 应用主导航
// ============================================================
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _pages = const [
    TranslatePage(),
    ProToolsPage(),
    LiveTranslatePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        height: 70,
        backgroundColor: const Color(0xFFF8F8FC),
        indicatorColor: const Color(0xFFE0E4FF),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.translate_outlined),
              selectedIcon: Icon(Icons.translate),
              label: '翻译'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'PRO 工具'),
          NavigationDestination(
              icon: Icon(Icons.multitrack_audio_outlined),
              selectedIcon: Icon(Icons.multitrack_audio),
              label: '实时翻译'),
        ],
      ),
    );
  }
}

class ProToolsPage extends StatelessWidget {
  const ProToolsPage({super.key});

  Future<void> _openTool(BuildContext context, ProFeature tool) async {
    if (!SubscriptionService.instance.isPremium) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }
    if (tool == ProFeature.ocr) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const OcrPage()));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${tool.label} 已准备好，请从这里进入')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = SubscriptionService.instance.isPremium;
    return Scaffold(
      appBar: AppBar(title: const Text('PRO 工具'), centerTitle: true, actions: [
        IconButton(
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()))),
      ]),
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF7F7FA), Color(0xFFEFF1F5)])),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: const Color(0xFFE9EBFF),
                  borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                const Icon(Icons.auto_awesome,
                    color: Color(0xFF5D6CFF), size: 30),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(
                        premium
                            ? 'PRO 已开启\n完整工具可直接使用'
                            : '升级 PRO\n解锁拍照、文档、术语库等工具',
                        style: const TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            fontWeight: FontWeight.w600))),
                if (!premium)
                  FilledButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PaywallScreen())),
                      child: const Text('升级')),
              ]),
            ),
            const SizedBox(height: 18),
            const Text('工具箱',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...ProFeature.values
                .where((t) => t != ProFeature.voiceChat)
                .map((tool) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE9EBFF),
                            child: Icon(tool.icon,
                                color: const Color(0xFF5D6CFF))),
                        title: Text(tool.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(tool == ProFeature.ocr
                            ? '拍照或从相册选图，识别并翻译文字'
                            : '专业翻译工作流工具'),
                        trailing: Icon(
                            premium
                                ? Icons.arrow_forward_ios
                                : Icons.lock_outline,
                            size: 17),
                        onTap: () => _openTool(context, tool),
                      ),
                    )),
          ],
        ),
      ),
    );
  }
}

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});
  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  bool _busy = false;
  String _status = '选择一张图片开始';

  Future<void> _pick(ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1280,
          maxHeight: 1280,
          requestFullMetadata: false,
          preferredCameraDevice: CameraDevice.rear);
      if (img == null) return;
      setState(() {
        _busy = true;
        _status = '正在识别…';
      });
      final bytes = await img.readAsBytes();
      final backend = kPaymentBackendBaseUrl;
      if (backend.isEmpty) throw Exception('后端地址未配置');
      final dataUrl =
          'data:${img.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}';
      final resp = await http
          .post(Uri.parse('$backend/ocr'),
              headers: SubscriptionService.instance.apiAuthHeaders,
              body: jsonEncode({'image': dataUrl, 'to': 'zh-CN'}))
          .timeout(const Duration(seconds: 45));
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      if (resp.statusCode != 200)
        throw Exception(data['error'] ?? 'OCR 失败（HTTP ${resp.statusCode}）');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '识别完成';
      });
      await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
                  title: const Text('拍照翻译结果'),
                  content: SingleChildScrollView(
                      child: Text(
                          '${data['target'] ?? ''}\n\n原文：${data['source'] ?? ''}')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'))
                  ]));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '识别失败';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('拍照失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照翻译')),
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.document_scanner_outlined,
                    size: 72, color: Color(0xFF5D6CFF)),
                const SizedBox(height: 16),
                Text(_status, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FilledButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('拍照')),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('相册')),
                ]),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator()
                ],
              ]))),
    );
  }
}

class LiveTranslatePage extends StatefulWidget {
  const LiveTranslatePage({super.key});
  @override
  State<LiveTranslatePage> createState() => _LiveTranslatePageState();
}

class _LiveTranslatePageState extends State<LiveTranslatePage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _ready = false, _listening = false, _busy = false;
  String _spoken = '', _translated = '点击麦克风开始实时翻译';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _ready = await _speech.initialize(onStatus: (s) {
      if (mounted && (s == 'done' || s == 'notListening'))
        setState(() => _listening = false);
    });
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (!_ready) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('语音不可用，请检查麦克风权限')));
      return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _spoken = '';
      _translated = '正在聆听…';
    });
    await _speech.listen(onResult: (r) async {
      if (!mounted) return;
      setState(() => _spoken = r.recognizedWords);
      if (r.finalResult && _spoken.trim().isNotEmpty) await _translate();
    });
  }

  Future<void> _translate() async {
    if (_busy || _spoken.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _translated = '翻译中…';
    });
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get',
          {'q': _spoken, 'langpair': 'zh-CN|en'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      final t = d['responseData']?['translatedText']?.toString() ?? '翻译失败';
      if (!mounted) return;
      setState(() {
        _translated = t;
        _busy = false;
      });
      await _tts.setLanguage('en-US');
      await _tts.speak(t);
    } catch (e) {
      if (mounted)
        setState(() {
          _translated = '翻译失败：$e';
          _busy = false;
        });
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实时翻译'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('你说的', style: TextStyle(color: Color(0xFF7B8192))),
                  const SizedBox(height: 8),
                  Text(_spoken.isEmpty ? '等待语音输入' : _spoken,
                      style: const TextStyle(fontSize: 20, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFE9EBFF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('翻译结果',
                      style: TextStyle(color: Color(0xFF5D6CFF))),
                  const SizedBox(height: 8),
                  Text(_translated,
                      style: const TextStyle(fontSize: 20, height: 1.4)),
                ],
              ),
            ),
            const Spacer(),
            IconButton.filled(
              onPressed: _toggle,
              iconSize: 42,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
            ),
            const SizedBox(height: 10),
            Text(_listening ? '正在聆听，再次点击结束' : '点击麦克风开始',
                style: const TextStyle(color: Color(0xFF7B8192))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 翻译页面
// ============================================================
class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  final TextEditingController _inputController = TextEditingController();
  String _resultText = '';
  bool _loading = false;
  // 免费版 500 字 / 高级版 5000 字（随订阅状态变化）
  int get _maxInputLength => SubscriptionService.instance.isPremium
      ? SubscriptionService.instance.premiumLimit
      : SubscriptionService.instance.freeLimit;

  // 语音识别
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // 语音合成
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  // AI 润色（PRO 权益）
  String _polishedText = '';
  bool _polishing = false;
  String _polishScene = 'natural';
  final List<Map<String, String>> _polishScenes = [
    {'id': 'natural', 'name': '地道'},
    {'id': 'business', 'name': '商务'},
    {'id': 'academic', 'name': '学术'},
    {'id': 'concise', 'name': '简洁'},
  ];

  // 术语库（PRO 专属工具，SharedPreferences 持久化：原文词 -> 首选译法）
  Map<String, String> _glossary = {};

  final List<Map<String, String>> _langList = [
    {'name': '中文', 'code': 'zh-CN'},
    {'name': '英语', 'code': 'en'},
    {'name': '日语', 'code': 'ja'},
    {'name': '韩语', 'code': 'ko'},
    {'name': '法语', 'code': 'fr'},
    {'name': '德语', 'code': 'de'},
    {'name': '俄语', 'code': 'ru'},
    {'name': '西班牙语', 'code': 'es'},
    {'name': '意大利语', 'code': 'it'},
    {'name': '葡萄牙语', 'code': 'pt'},
    {'name': '阿拉伯语', 'code': 'ar'},
    {'name': '印地语', 'code': 'hi'},
    {'name': '土耳其语', 'code': 'tr'},
    {'name': '荷兰语', 'code': 'nl'},
  ];

  // TTS 语言代码映射
  final Map<String, String> _ttsLangMap = {
    'zh-CN': 'zh-CN',
    'en': 'en-US',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'ru': 'ru-RU',
    'es': 'es-ES',
    'it': 'it-IT',
    'pt': 'pt-PT',
    'ar': 'ar-SA',
    'hi': 'hi-IN',
    'tr': 'tr-TR',
    'nl': 'nl-NL',
  };

  // 语音识别 locale 映射
  final Map<String, String> _speechLocaleMap = {
    'zh-CN': 'zh_CN',
    'en': 'en_US',
    'ja': 'ja_JP',
    'ko': 'ko_KR',
    'fr': 'fr_FR',
    'de': 'de_DE',
    'ru': 'ru_RU',
    'es': 'es_ES',
    'it': 'it_IT',
    'pt': 'pt_PT',
    'ar': 'ar_SA',
    'hi': 'hi_IN',
    'tr': 'tr_TR',
    'nl': 'nl_NL',
  };

  int _fromIndex = 0;
  int _toIndex = 1;

  @override
  void initState() {
    super.initState();
    // 加载本地订阅状态（高级功能解锁）
    SubscriptionService.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    _initSpeech();
    _initTts();
    _loadGlossary();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        // 用 maybeOf,避免 widget 已卸载时 throw 闪退
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(content: Text('语音识别出错，请重试')),
        );
      },
    );
    if (mounted) setState(() {});
  }

  void _initTts() {
    // 所有回调都加 mounted 守卫,并用 maybeOf 避免 widget 卸载后触发闪退
    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    });
    _flutterTts.setErrorHandler((msg) {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('语音播报出错')),
      );
    });
    _flutterTts.setCancelHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('语音识别不可用，请检查权限设置')),
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
    } else {
      final locale = _speechLocaleMap[_langList[_fromIndex]['code']] ?? 'en_US';
      await _speech.listen(
        localeId: locale,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
        ),
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _inputController.text = result.recognizedWords;
            _inputController.selection = TextSelection.fromPosition(
              TextPosition(offset: _inputController.text.length),
            );
          });
        },
      );
      if (!mounted) return;
      setState(() => _isListening = true);
    }
  }

  Future<void> _toggleSpeaking() async {
    if (_resultText.isEmpty) return;
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    } else {
      final ttsLang = _ttsLangMap[_langList[_toIndex]['code']] ?? 'en-US';
      await _flutterTts.setLanguage(ttsLang);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(_resultText);
      if (!mounted) return;
      setState(() => _isSpeaking = true);
    }
  }

  Future<void> doTranslate() async {
    final text = _inputController.text.trim();
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入要翻译的文本')),
      );
      return;
    }
    if (text.length > _maxInputLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文本过长，请控制在 $_maxInputLength 字以内')),
      );
      return;
    }
    if (_fromIndex == _toIndex) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('源语言和目标语言不能相同')),
      );
      return;
    }

    // 停止语音
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _resultText = '';
    });

    final from = _langList[_fromIndex]['code']!;
    final to = _langList[_toIndex]['code']!;

    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': text,
        'langpair': '$from|$to',
      });

      final response = await http.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      // 使用 bodyBytes 显式 UTF-8 解码，避免编码问题
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw Exception('无效的响应格式');
      }

      final responseData = data['responseData'];
      final translatedText = responseData is Map<String, dynamic>
          ? responseData['translatedText'] as String?
          : null;

      if (translatedText == null || translatedText.isEmpty) {
        throw Exception('未返回翻译结果');
      }

      // 检测配额耗尽警告
      if (translatedText.startsWith('MYMEMORY WARNING')) {
        throw Exception('API 调用配额已耗尽，请稍后再试');
      }

      if (!mounted) return;
      setState(() {
        _resultText = translatedText;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultText = '翻译失败，请稍后重试';
        });
        debugPrint('翻译异常: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void copyResult() {
    if (_resultText.isEmpty) return;
    if (!mounted) return;
    Clipboard.setData(ClipboardData(text: _resultText));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  // ---- PRO 专属工具 ----

  Future<void> _loadGlossary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('lingua_glossary_v1');
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _glossary = map.map((k, v) => MapEntry(k, v as String));
      }
    } catch (_) {}
  }

  Future<void> _saveGlossary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lingua_glossary_v1', jsonEncode(_glossary));
    } catch (_) {}
  }

  /// 把术语库中的「原文词 -> 首选译法」批量替换到文本中。
  String _applyGlossary(String text) {
    var out = text;
    for (final e in _glossary.entries) {
      out = out.replaceAll(e.key, e.value);
    }
    return out;
  }

  /// 导出 / 分享：复制为 Markdown 到剪贴板。
  void _exportResult() {
    if (_resultText.isEmpty) return;
    final md = '# 翻译结果\n\n$_resultText\n';
    Clipboard.setData(ClipboardData(text: md));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('已复制为 Markdown 到剪贴板')));
  }

  /// 术语库管理弹窗（PRO）。
  Future<void> _openGlossary() async {
    final termCtrl = TextEditingController();
    final replCtrl = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('术语库（PRO）'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: termCtrl,
                        decoration: const InputDecoration(labelText: '原文词'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: replCtrl,
                        decoration: const InputDecoration(labelText: '首选译法'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('已添加：'),
                ),
                ..._glossary.entries.map(
                  (e) => ListTile(
                    dense: true,
                    title: Text('${e.key} → ${e.value}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () {
                        _glossary.remove(e.key);
                        _saveGlossary();
                        setSt(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            ElevatedButton(
              onPressed: () {
                final t = termCtrl.text.trim();
                final r = replCtrl.text.trim();
                if (t.isNotEmpty) {
                  _glossary[t] = r;
                  _saveGlossary();
                  termCtrl.clear();
                  replCtrl.clear();
                  setSt(() {});
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 实时语音对话（PRO）：听一句 -> 翻译 -> 语音播报。
  Future<void> _openVoiceChat() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('实时语音对话（PRO）'),
        content: const Text('点按下方按钮，说一句话，自动翻译并用语音播报。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _voiceRound(false);
            },
            child: const Text('我说（源→目标）'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _voiceRound(true);
            },
            child: const Text('对方说（目标→源）'),
          ),
        ],
      ),
    );
  }

  Future<void> _voiceRound(bool reverse) async {
    if (!_speechAvailable) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('语音识别不可用，请检查权限')));
      return;
    }
    final fromIdx = reverse ? _toIndex : _fromIndex;
    final toIdx = reverse ? _fromIndex : _toIndex;
    final completer = Completer<String>();
    if (_isListening) await _speech.stop();
    await _speech.listen(
      localeId: _speechLocaleMap[_langList[fromIdx]['code']] ?? 'en_US',
      listenOptions:
          stt.SpeechListenOptions(listenMode: stt.ListenMode.dictation),
      onResult: (r) {
        if (r.finalResult) completer.complete(r.recognizedWords);
      },
    );
    if (!mounted) return;
    final spoken = await completer.future
        .timeout(const Duration(seconds: 15), onTimeout: () => '');
    await _speech.stop();
    if (spoken.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('没听清，请重试')));
      return;
    }
    final translated = await _voiceTranslate(
        spoken, _langList[fromIdx]['code']!, _langList[toIdx]['code']!);
    if (!mounted) return;
    final ttsLang = _ttsLangMap[_langList[toIdx]['code']] ?? 'en-US';
    await _flutterTts.setLanguage(ttsLang);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(translated);
    setState(() {
      _inputController.text = spoken;
      _resultText = translated;
    });
  }

  Future<String> _voiceTranslate(String text, String from, String to) async {
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': text,
        'langpair': '$from|$to',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return text;
      final data = json.decode(utf8.decode(response.bodyBytes));
      final rd = data is Map<String, dynamic> ? data['responseData'] : null;
      final t =
          rd is Map<String, dynamic> ? rd['translatedText'] as String? : null;
      if (t == null || t.isEmpty || t.startsWith('MYMEMORY WARNING'))
        return text;
      return t;
    } catch (_) {
      return text;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 文档翻译（PRO）：选 TXT/MD/CSV/DOCX → 提取文本 → 分块翻译 → 结果可复制。
  Future<void> _openDocument() async {
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showSnack('无法读取文件内容');
      return;
    }
    final name = file.name.toLowerCase();
    final text = name.endsWith('.docx')
        ? _extractDocxText(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    if (text.trim().isEmpty) {
      _showSnack('未提取到文本（PDF 暂不支持，请先转成 TXT/DOCX）');
      return;
    }
    final from = _langList[_fromIndex]['code']!;
    final to = _langList[_toIndex]['code']!;
    final progress = ValueNotifier<String>('准备中…');
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('文档翻译'),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, v, __) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 12),
              Expanded(child: Text(v)),
            ],
          ),
        ),
      ),
    ));
    try {
      final out = await _translateDocument(text, from, to, (d, t) {
        progress.value = '翻译中 $d/$t';
      });
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      _showDocumentResult(out);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      _showSnack('翻译失败：$e');
    }
  }

  /// 文档翻译结果展示（可复制译文）。
  void _showDocumentResult(String translated) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文档翻译结果'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: SingleChildScrollView(child: SelectableText(translated)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: translated));
              Navigator.pop(ctx);
              _showSnack('译文已复制');
            },
            child: const Text('复制译文'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 拍照 / 选图 OCR 翻译（PRO）：选图 → 后端视觉 LLM 识别并翻译。
  Future<void> _openOcr() async {
    if (!mounted) return;
    final source = await showDialog<ImageSource?>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('拍照翻译'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, ImageSource.camera),
            child: const ListTile(
                leading: Icon(Icons.camera_alt), title: Text('拍照')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, ImageSource.gallery),
            child: const ListTile(
                leading: Icon(Icons.photo_library), title: Text('从相册选择')),
          ),
        ],
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    // 限制尺寸与质量：原图常 3000px+/10MB+，整张传 OCR 会拖垮上传与视觉模型推理（前端 45s 超时内拿不到回包 → 一直转圈）。
    XFile? img;
    try {
      img = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1280,
        maxHeight: 1280,
        requestFullMetadata: false,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(source == ImageSource.camera
          ? '无法调用相机：请到 设置 → 隐私与安全性 → 相机，允许 Lingua Link 使用相机'
          : '无法打开相册：请到 设置 → 隐私与安全性 → 照片，允许 Lingua Link 访问照片');
      debugPrint('[ocr] image_picker error: $e');
      return;
    }
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final mime = img.mimeType ?? 'image/png';
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final backend = kPaymentBackendBaseUrl;
    if (backend.isEmpty) {
      _showSnack('OCR 需部署后端（配置 PAYMENT_BACKEND，并接入支持视觉的 LLM）');
      return;
    }
    final progress = ValueNotifier<String>('识别中…');
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('拍照翻译'),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, v, __) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 12),
              Expanded(child: Text(v)),
            ],
          ),
        ),
      ),
    ));
    final to = _langList[_toIndex]['code']!;
    try {
      final resp = await http
          .post(
            Uri.parse('$backend/ocr'),
            headers: SubscriptionService.instance.apiAuthHeaders,
            body: json.encode({'image': dataUrl, 'to': to}),
          )
          .timeout(const Duration(seconds: 45));
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      if (resp.statusCode == 401) {
        await SubscriptionService.instance.clearMembership();
        if (mounted) setState(() {});
        _showSnack('会员凭证已失效，请重新在「兑换码」页兑换');
        return;
      }
      if (resp.statusCode != 200) {
        _showSnack('OCR 失败（HTTP ${resp.statusCode}）');
        return;
      }
      final data = json.decode(utf8.decode(resp.bodyBytes));
      _showOcrResult(
          data['source']?.toString() ?? '', data['target']?.toString() ?? '');
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      _showSnack('OCR 失败：$e');
    }
  }

  /// OCR 结果展示（原文 + 译文，可复制译文）。
  void _showOcrResult(String source, String target) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拍照翻译结果'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('识别原文',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(source.isEmpty ? '（未识别到文字）' : source),
                const SizedBox(height: 16),
                const Text('译文', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(target.isEmpty ? '（无）' : target),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: target));
              Navigator.pop(ctx);
              _showSnack('译文已复制');
            },
            child: const Text('复制译文'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 从 DOCX 字节提取纯文本（解析 word/document.xml 中的 <w:t>）。
  String _extractDocxText(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? docFile;
      for (final f in archive.files) {
        if (f.name == 'word/document.xml') {
          docFile = f;
          break;
        }
      }
      if (docFile == null) return '';
      final xml = utf8.decode(docFile.content as List<int>);
      final withBreaks = xml.replaceAll(RegExp(r'</w:p>'), '\n');
      final matches =
          RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true).allMatches(withBreaks);
      final sb = StringBuffer();
      for (final m in matches) {
        sb.write(_xmlUnescape(m.group(1) ?? ''));
      }
      return sb.toString().trim();
    } catch (_) {
      return '';
    }
  }

  String _xmlUnescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');

  /// 把长文本切成 ~400 字符的块（尽量按段落边界）。
  List<String> _chunkText(String text) {
    final paras = text.split('\n');
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final p in paras) {
      final piece = p.trim();
      if (piece.isEmpty) continue;
      if (buf.isNotEmpty && buf.length + piece.length > 400) {
        chunks.add(buf.toString().trim());
        buf.clear();
      }
      buf.write(piece);
      buf.write('\n');
    }
    if (buf.isNotEmpty) chunks.add(buf.toString().trim());
    return chunks;
  }

  /// 整篇文档分块翻译（MyMemory，免费、无需密钥）。
  Future<String> _translateDocument(String text, String from, String to,
      void Function(int done, int total) onProgress) async {
    final chunks = _chunkText(text);
    if (chunks.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < chunks.length; i++) {
      onProgress(i + 1, chunks.length);
      final t = await _translateViaMymemory(chunks[i], from, to);
      sb.write(t);
      sb.write('\n\n');
    }
    return sb.toString().trim();
  }

  /// 单段走 MyMemory 翻译（文档 / 语音复用）。
  Future<String> _translateViaMymemory(
      String text, String from, String to) async {
    if (text.trim().isEmpty) return '';
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': '$from|$to',
    });
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return text;
      final data = json.decode(utf8.decode(resp.bodyBytes));
      final rd = data is Map<String, dynamic> ? data['responseData'] : null;
      final t =
          rd is Map<String, dynamic> ? rd['translatedText'] as String? : null;
      if (t == null || t.isEmpty || t.startsWith('MYMEMORY WARNING'))
        return text;
      return t;
    } catch (_) {
      return text;
    }
  }

  /// 统一的 PRO 工具入口：未开通会员先跳付费墙，否则执行对应功能。
  void _openProTool(ProFeature tool) {
    if (!SubscriptionService.instance.isPremium) {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }
    switch (tool) {
      case ProFeature.export:
        _exportResult();
        break;
      case ProFeature.glossary:
        _openGlossary();
        break;
      case ProFeature.voiceChat:
        _openVoiceChat();
        break;
      case ProFeature.document:
        _openDocument();
        break;
      case ProFeature.ocr:
        _openOcr();
        break;
    }
  }

  Future<void> _aiPolish() async {
    // PRO 权益：未开通会员则引导去付费墙
    if (!SubscriptionService.instance.isPremium) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      if (mounted) setState(() {});
      return;
    }
    if (_resultText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先翻译出内容再润色')),
      );
      return;
    }
    final backend = kPaymentBackendBaseUrl;
    if (backend.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 润色需部署后端（配置 PAYMENT_BACKEND）')),
      );
      return;
    }
    setState(() {
      _polishing = true;
      _polishedText = '';
    });
    try {
      final resp = await http
          .post(
            Uri.parse('$backend/ai-polish'),
            headers: SubscriptionService.instance.apiAuthHeaders,
            body: json.encode({'text': _resultText, 'scene': _polishScene}),
          )
          .timeout(const Duration(seconds: 30));
      final data = json.decode(utf8.decode(resp.bodyBytes));
      if (!mounted) return;
      if (resp.statusCode == 401) {
        await SubscriptionService.instance.clearMembership();
        if (mounted) setState(() {});
        throw Exception('会员凭证已失效，请重新在「兑换码」页兑换');
      }
      if (resp.statusCode != 200 || data['polished'] == null) {
        throw Exception(data['error'] ?? '润色失败');
      }
      setState(() => _polishedText = data['polished'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('润色失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  void clearAll() {
    _inputController.clear();
    if (!mounted) return;
    setState(() {
      _resultText = '';
    });
  }

  void swapLang() {
    setState(() {
      final temp = _fromIndex;
      _fromIndex = _toIndex;
      _toIndex = temp;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _flutterTts.stop();
    _speech.stop();
    super.dispose();
  }

  // ============================================================
  // UI 构建方法
  // ============================================================

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(255, 255, 255, 0.82),
              Color.fromRGBO(255, 255, 255, 0.58),
            ],
          ),
          border: Border.all(
            color: const Color.fromRGBO(255, 255, 255, 0.8),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(93, 108, 255, 0.10),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
            BoxShadow(
              color: Color.fromRGBO(255, 255, 255, 0.6),
              blurRadius: 1,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 顶部玻璃反光弧
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0),
                      Colors.white.withOpacity(0.95),
                      Colors.white.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required int value,
    required String label,
    required ValueChanged<int?> onChanged,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(255, 255, 255, 0.82),
              Color.fromRGBO(255, 255, 255, 0.52),
            ],
          ),
          border: Border.all(
            color: const Color.fromRGBO(255, 255, 255, 0.75),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5D6CFF).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 顶部高光弧
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0),
                      Colors.white.withOpacity(0.9),
                      Colors.white.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
            DropdownButtonFormField<int>(
              value: value,
              items: _langList.asMap().entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(
                    entry.value['name']!,
                    style: const TextStyle(
                      color: Color(0xFF232F46),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF5D6CFF),
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(
                  color: Color(0xFF5F6A85),
                  fontWeight: FontWeight.w500,
                ),
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 14,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard() {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: _buildDropdownField(
                value: _fromIndex,
                label: '源语言',
                onChanged: (value) {
                  if (value != null) setState(() => _fromIndex = value);
                },
              ),
            ),
            const SizedBox(width: 12),
            // 液态玻璃圆形交换按钮
            LiquidGlassCircleButton(
              onPressed: swapLang,
              size: 48,
              child: const Icon(Icons.swap_horiz),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdownField(
                value: _toIndex,
                label: '目标语言',
                onChanged: (value) {
                  if (value != null) setState(() => _toIndex = value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            TextField(
              controller: _inputController,
              maxLines: 6,
              style: const TextStyle(color: Color(0xFF232F46)),
              decoration: InputDecoration(
                hintText: _isListening ? '正在聆听...' : '在此输入或语音输入翻译文字',
                hintStyle: TextStyle(
                  color: _isListening
                      ? const Color(0xFF5D6CFF)
                      : Colors.grey.shade500,
                ),
                filled: true,
                fillColor: const Color.fromRGBO(255, 255, 255, 0.82),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                      color: Color.fromRGBO(255, 255, 255, 0.8)),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 字符计数
                      Text(
                        '${_inputController.text.length}/$_maxInputLength',
                        style: TextStyle(
                          fontSize: 12,
                          color: _inputController.text.length > _maxInputLength
                              ? Colors.red.shade400
                              : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 语音输入按钮
                      LiquidGlassCircleButton(
                        onPressed: _toggleListening,
                        size: 44,
                        isActive: _isListening,
                        accentColor: const Color(0xFF5D6CFF),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_isListening)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '正在聆听，请说话...',
                      style: TextStyle(
                        color: Color(0xFF5D6CFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: LiquidGlassButton(
            onPressed: _loading ? null : doTranslate,
            isPrimary: true,
            accentColor: const Color(0xFF5D6CFF),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('开始翻译'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: LiquidGlassButton(
            onPressed: clearAll,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: const Text('清空'),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '翻译结果：',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                // 语音播报按钮
                LiquidGlassCircleButton(
                  onPressed: _resultText.isEmpty ? null : _toggleSpeaking,
                  size: 40,
                  isActive: _isSpeaking,
                  accentColor: const Color(0xFF3A7D44),
                  child: Icon(
                    _isSpeaking ? Icons.stop : Icons.volume_up,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _resultText.isNotEmpty ? _resultText : '等待翻译...',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 18),
            LiquidGlassButton(
              onPressed: _resultText.isEmpty ? null : copyResult,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy, size: 18),
                  SizedBox(width: 8),
                  Text('复制'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('AI 润色',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('PRO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _polishScenes.map((s) {
                final selected = _polishScene == s['id'];
                return ChoiceChip(
                  label: Text(s['name']!),
                  selected: selected,
                  onSelected: (_) => setState(() => _polishScene = s['id']!),
                  selectedColor: const Color(0xFF5D6CFF),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF4E5875),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _polishing
                ? const Center(child: CircularProgressIndicator())
                : LiquidGlassButton(
                    onPressed: _resultText.isEmpty ? null : _aiPolish,
                    isPrimary: true,
                    accentColor: const Color(0xFF5D6CFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: const Text('一键润色'),
                  ),
            if (_polishedText.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(245, 246, 255, 0.9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color.fromRGBO(93, 108, 255, 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('润色结果',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5D6CFF),
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 6),
                    Text(_polishedText,
                        style: const TextStyle(fontSize: 15, height: 1.5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProToolsPage())),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('打开 PRO 工具箱'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 应用小图标 —— 呼应桌面 icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF7B82FF),
                    Color(0xFF5D6CFF),
                    Color(0xFF4250DC),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5D6CFF).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                '译',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'lingua link',
              style: TextStyle(
                color: Color.fromARGB(255, 43, 51, 69),
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '兑换码',
            icon: const Icon(Icons.redeem_outlined, color: Color(0xFF5D6CFF)),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RedeemScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: '高级功能',
            icon: Icon(
              Icons.workspace_premium_outlined,
              color: SubscriptionService.instance.isPremium
                  ? const Color(0xFFFFB300)
                  : const Color(0xFF5D6CFF),
            ),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: '卖家确认',
            icon:
                const Icon(Icons.storefront_outlined, color: Color(0xFF5D6CFF)),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SellerConfirmScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          if (SubscriptionService.instance.isPremium)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('PRO',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ),
            ),
        ],
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      ),
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7F7FA), Color(0xFFEFF1F5)],
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + kToolbarHeight + 16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLanguageCard(),
              const SizedBox(height: 18),
              _buildInputCard(),
              const SizedBox(height: 18),
              _buildActionRow(),
              const SizedBox(height: 22),
              _buildResultCard(),
            ],
          ),
        ),
      ),
    );
  }
}
