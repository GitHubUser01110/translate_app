import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'deepseek_service.dart';
import 'baidu_service.dart';
import 'keyboard_simulator.dart';
import 'config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  bool isFirstRun = await ConfigService.isFirstRun();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(500, 360),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    windowButtonVisibility: false,
    minimumSize: Size(350, 150),
    maximumSize: Size(1000, 1000),
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(false);
    await windowManager.setAsFrameless();
    await windowManager.setPreventClose(true);
    
    if (isFirstRun) {
      await windowManager.show();
    } else {
      await windowManager.hide();
    }
  });

  runApp(MyApp(isFirstRun: isFirstRun));
}

class MyApp extends StatelessWidget {
  final bool isFirstRun;
  
  const MyApp({super.key, required this.isFirstRun});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Translate_X',
      theme: ThemeData(
        fontFamily: "Microsoft YaHei",
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      home: TranslationPage(isFirstRun: isFirstRun),
    );
  }
}

class TranslationPage extends StatefulWidget {
  final bool isFirstRun;
  
  const TranslationPage({super.key, required this.isFirstRun});

  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> with SingleTickerProviderStateMixin, TrayListener, WindowListener {
  final DeepSeekService _dsApi = DeepSeekService();
  final BaiduService _baiduApi = BaiduService();
  
  final GlobalKey _contentKey = GlobalKey();
  final ScreenCapturer _capturer = ScreenCapturer.instance;
  
  String _originalText = "";
  String _resultText = "按 Alt+Q 划词翻译\n按 Alt+W 截图翻译"; 
  bool _isLoading = false;
  bool _showOriginal = true;
  
  late bool _showSettings; 
  
  final TextEditingController _dsKeyCtrl = TextEditingController();
  final TextEditingController _baiduAkCtrl = TextEditingController();
  final TextEditingController _baiduSkCtrl = TextEditingController();

  bool _isManuallyResized = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    // 必须先添加监听，再初始化托盘
    trayManager.addListener(this);
    windowManager.addListener(this);
    
    _showSettings = widget.isFirstRun;
    if (widget.isFirstRun) {
      _resultText = ""; 
    }
    
    _initializeApp();
    
    // 稍微延后一点初始化托盘，确保资源加载就绪
    Future.delayed(Duration.zero, () {
      _initSystemTray();
    });
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  // --- 托盘初始化 ---
  Future<void> _initSystemTray() async {
    // 1. 设置图标
    String iconPath = 'assets/app_icon.ico'; 
    try {
      final directory = await getTemporaryDirectory();
      final targetPath = '${directory.path}/tray_icon.ico';
      
      // 从 assets 读取文件
      ByteData data = await rootBundle.load(iconPath);
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      
      // 写入临时文件 (因为 tray_manager 需要本地路径)
      File file = File(targetPath);
      await file.writeAsBytes(bytes);
      
      await trayManager.setIcon(targetPath);
    } catch (e) {
      debugPrint("托盘图标设置失败: $e");
    }
  }

  // 左键点击：显示窗口
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  // [重点修复] 右键点击：动态构建并弹出菜单
  // 这种写法在 Windows 上最稳，点击的瞬间才生成菜单
  @override
  void onTrayIconRightMouseDown() async {
    // 1. 定义菜单项
    List<MenuItem> items = [
      MenuItem(key: 'show_window', label: '显示主界面'),
      MenuItem(key: 'settings', label: '设置'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出 Translate_X'),
    ];
    
    // 2. 重新设置菜单 (确保它是最新的)
    await trayManager.setContextMenu(Menu(items: items));
    
    // 3. 强制弹出
    await trayManager.popUpContextMenu();
  }

  // 菜单点击回调
  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        windowManager.focus();
        break;
      case 'settings':
        windowManager.show();
        windowManager.focus();
        Future.delayed(const Duration(milliseconds: 100), () {
          _openSettings();
        });
        break;
      case 'exit_app':
        // [优化退出逻辑]
        
        // 1. 移除托盘图标 (防止残留幽灵图标)
        await trayManager.destroy();
        
        // 2. (可选) 注销快捷键，虽然进程杀掉后系统会自动回收，但这样更规范
        await hotKeyManager.unregisterAll();

        // 3. 强制结束 Dart 进程 (0 表示正常退出)
        // 这比 windowManager.destroy() 快得多
        exit(0);
    }
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  void _initializeApp() async {
    await _dsApi.initialize();
    await _baiduApi.initialize();
    
    bool hasDsKey = _dsApi.hasApiKey();
    if (!widget.isFirstRun && !hasDsKey) {
      setState(() => _showSettings = true);
    }
    
    _dsKeyCtrl.text = await ConfigService.getDeepSeekKey() ?? "";
    var baiduKeys = await ConfigService.getBaiduKeys();
    _baiduAkCtrl.text = baiduKeys['apiKey'] ?? "";
    _baiduSkCtrl.text = baiduKeys['secretKey'] ?? "";

    _initHotkeys();
  }

  void _initHotkeys() async {
    await hotKeyManager.register(
      HotKey(key: PhysicalKeyboardKey.keyQ, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system),
      keyDownHandler: (_) => _handleTextSelection(),
    );

    await hotKeyManager.register(
      HotKey(key: PhysicalKeyboardKey.keyW, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system),
      keyDownHandler: (_) => _handleScreenOCR(),
    );
  }

  Future<void> _handleScreenOCR() async {
    if (!_baiduApi.hasKeys()) {
      _restoreWindow("未配置 OCR Key，请前往设置配置");
      _openSettings(); 
      return;
    }

    await windowManager.hide();
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      Directory directory = await getTemporaryDirectory();
      String imagePath = '${directory.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png';

      CapturedData? capturedData = await _capturer.capture(
        mode: CaptureMode.region, 
        imagePath: imagePath,
      );

      if (capturedData != null && File(imagePath).existsSync()) {
        _startLoadingState("正在识别文字..."); 
        String? ocrText = await _baiduApi.recognizeText(File(imagePath));
        try { File(imagePath).delete(); } catch (_) {}

        if (ocrText != null && ocrText.trim().isNotEmpty && !ocrText.contains("OCR 错误")) {
          _startTranslationFlow(ocrText);
        } else {
          _restoreWindow(ocrText ?? "未识别到文字");
        }
      } else {
        _restoreWindow("截图已取消");
      }
    } catch (e) {
      _restoreWindow("OCR 异常: $e");
    }
  }

  Future<void> _handleTextSelection() async {
    await windowManager.hide();
    await Future.delayed(const Duration(milliseconds: 100));
    KeyboardSimulator.simulateCopy();
    await Future.delayed(const Duration(milliseconds: 300));
    
    ClipboardData? clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    String text = clipboardData?.text ?? "";
    
    if (text.isNotEmpty) {
      _startTranslationFlow(text);
    }
  }

  Future<void> _startLoadingState(String text) async {
    if (!mounted) return;
    setState(() {
      _showSettings = false;
      _isLoading = true;
      _resultText = text;
      _originalText = "";
    });
    
    Offset mousePos = await screenRetriever.getCursorScreenPoint();
    Rect currentBounds = await windowManager.getBounds();
    await windowManager.setBounds(Rect.fromLTWH(
      mousePos.dx + 10, mousePos.dy + 15, currentBounds.width, 280 
    ));
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _startTranslationFlow(String textToTranslate) async {
    if (!_dsApi.hasApiKey()) {
      _openSettings();
      _restoreWindow("请先配置 DeepSeek Key");
      return;
    }

    if (textToTranslate.trim().isEmpty) return;

    setState(() {
      _showSettings = false;
      _isManuallyResized = false;
      _originalText = textToTranslate;
      _isLoading = true;
      _resultText = "正在翻译...";
    });

    if (!await windowManager.isVisible()) {
       Offset mousePos = await screenRetriever.getCursorScreenPoint();
       Rect currentBounds = await windowManager.getBounds();
       await windowManager.setBounds(Rect.fromLTWH(
         mousePos.dx + 10, mousePos.dy + 15, currentBounds.width, 280 
       ));
       await windowManager.show();
       await windowManager.focus();
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFitWindowHeight());

    String translated = await _dsApi.translate(textToTranslate);

    if (mounted) {
      setState(() {
        _resultText = translated;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFitWindowHeight());
    }
  }

  Future<void> _autoFitWindowHeight() async {
    if (_showSettings || _isManuallyResized) return;
    final RenderBox? renderBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      double newHeight = renderBox.size.height + 60; 
      newHeight = newHeight.clamp(200, 800);
      Rect currentBounds = await windowManager.getBounds();
      await windowManager.setSize(Size(currentBounds.width, newHeight));
    }
  }

  Future<void> _restoreWindow(String? message) async {
    if (!mounted) return;
    await windowManager.show();
    await windowManager.focus();
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2), backgroundColor: message.contains("异常") || message.contains("未配置") ? Colors.red : Colors.grey.shade800),
      );
    }
  }

  void _closeWindow() { windowManager.hide(); }
  void _toggleOriginal() {
    setState(() => _showOriginal = !_showOriginal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFitWindowHeight());
  }
  
  void _openSettings() async {
    setState(() => _showSettings = true);
    Rect bounds = await windowManager.getBounds();
    if (bounds.height < 450) {
      await windowManager.setSize(Size(bounds.width, 450));
    }
  }

  Future<void> _saveAllKeys() async {
    final dsKey = _dsKeyCtrl.text.trim();
    final bdAk = _baiduAkCtrl.text.trim();
    final bdSk = _baiduSkCtrl.text.trim();

    if (dsKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DeepSeek Key 不能为空'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isVerifying = true);

    try {
      _dsApi.setApiKey(dsKey);
      String testTrans = await _dsApi.translate("Hi");
      if (testTrans.contains("配置") || testTrans.contains("失败")) {
        throw "DeepSeek Key 无效";
      }

      if (bdAk.isEmpty && bdSk.isEmpty) {
        _baiduApi.setKeys("", ""); 
      } else if (bdAk.isNotEmpty && bdSk.isNotEmpty) {
        _baiduApi.setKeys(bdAk, bdSk);
        await _baiduApi.verifyKeys(bdAk, bdSk);
      } else {
        throw "百度 OCR 配置必须同时填写 AK 和 SK，或者都不填";
      }

      await ConfigService.saveDeepSeekKey(dsKey);
      await ConfigService.saveBaiduKeys(bdAk, bdSk);
      await ConfigService.setNotFirstRun();

      if (!mounted) return;
      
      setState(() {
        _showSettings = false;
        if (_resultText.isEmpty || _resultText.contains("配置")) {
           _resultText = "配置成功！\nAlt+Q 划词 | Alt+W 截图";
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存'), backgroundColor: Colors.green));
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFitWindowHeight());

    } catch (e) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _copyTranslation() async {
    await Clipboard.setData(ClipboardData(text: _resultText));
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
  }

  Widget _buildTranslationView() {
    return Column(
      key: const ValueKey('translation_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showOriginal && _originalText.isNotEmpty) ...[
          Text("原文", style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(_originalText, style: TextStyle(color: Colors.grey.shade800, fontSize: 13, height: 1.4)),
          ),
          const SizedBox(height: 16),
        ],
        Text(_isLoading ? "处理中..." : "译文", style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isLoading ? Colors.blue.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _isLoading ? Colors.blue.shade100 : Colors.green.shade200),
          ),
          child: _isLoading
              ? Center(child: Padding(padding: const EdgeInsets.all(8.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade400))))
              : SelectableText(_resultText, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5)),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return Container(
      key: const ValueKey('settings_view'),
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("1. 翻译配置 (必填)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _buildInput(_dsKeyCtrl, "sk-...", "DeepSeek API Key"),
          
          const SizedBox(height: 20),
          const Text("2. 截图OCR配置 (选填)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text("仅使用截图功能时需要，百度智能云 AK/SK", style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          _buildInput(_baiduAkCtrl, "API Key (AK)", "百度 API Key"),
          const SizedBox(height: 8),
          _buildInput(_baiduSkCtrl, "Secret Key (SK)", "百度 Secret Key"),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isVerifying ? null : () { ConfigService.clearAllKeys(); setState(() {_dsKeyCtrl.clear(); _baiduAkCtrl.clear(); _baiduSkCtrl.clear();}); },
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                child: const Text("清空"),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isVerifying ? null : _saveAllKeys,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
                child: _isVerifying
                    ? Row(mainAxisSize: MainAxisSize.min, children: const [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)), SizedBox(width: 8), Text("验证中...")])
                    : const Text("保存"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String hint, String label) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label, hintText: hint, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      style: const TextStyle(fontSize: 13, fontFamily: "Monospace"),
      obscureText: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: RepaintBoundary(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 4))]),
            child: Column(
              children: [
                Container(
                  height: 38,
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onPanDown: (_) => windowManager.startDragging(),
                          behavior: HitTestBehavior.translucent,
                          child: Row(children: [Icon(Icons.translate_rounded, size: 16, color: Colors.blue.shade600), const SizedBox(width: 8), Text(_showSettings ? "配置中心" : "DeepSeek 翻译助手", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800))]),
                        ),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!_showSettings) ...[
                          _HeaderBtn(icon: _showOriginal ? Icons.visibility : Icons.visibility_off, tooltip: "原文开关", onTap: _toggleOriginal),
                          _HeaderBtn(icon: Icons.copy_rounded, tooltip: "复制", onTap: _copyTranslation),
                          _HeaderBtn(icon: Icons.settings_rounded, tooltip: "设置", onTap: _openSettings),
                          Container(width: 1, height: 16, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
                        ],
                        _HeaderBtn(icon: Icons.close_rounded, tooltip: "隐藏", onTap: _closeWindow),
                      ]),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Container(
                      key: _contentKey, padding: const EdgeInsets.all(16),
                      child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), switchInCurve: Curves.easeInOutCubic, switchOutCurve: Curves.easeInOutCubic, transitionBuilder: (Widget child, Animation<double> animation) { return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.01, 0), end: Offset.zero).animate(animation), child: child)); }, child: _showSettings ? _buildSettingsView() : _buildTranslationView()),
                    ),
                  ),
                ),
                GestureDetector(
                  onPanDown: (_) { windowManager.startResizing(ResizeEdge.bottomRight); _isManuallyResized = true; },
                  behavior: HitTestBehavior.translucent,
                  child: Container(height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))), child: Stack(children: [Center(child: Text("Alt + Q 划词 | Alt + W 截图", style: TextStyle(fontSize: 10, color: Colors.grey.shade300))), Positioned(right: 8, bottom: 8, child: Icon(Icons.signal_cellular_4_bar, size: 10, color: Colors.grey.shade400))])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final String tooltip;
  const _HeaderBtn({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) { return Tooltip(message: tooltip, child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(4), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(icon, size: 16, color: Colors.grey.shade600))))); }
}