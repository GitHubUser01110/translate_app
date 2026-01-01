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
import 'ocr_service.dart';
import 'keyboard_simulator.dart';
import 'config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  bool isFirstRun = await ConfigService.isFirstRun();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(450, 300), // 默认大小略微调整
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    windowButtonVisibility: false,
    minimumSize: Size(350, 150),
    maximumSize: Size(800, 1000),
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
          seedColor: const Color(0xFF2563EB), // 使用更专业的深蓝色
          brightness: Brightness.light,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          isDense: true,
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
  final OcrService _ocrApi = OcrService(); // 替换为 OCR 服务
  
  final GlobalKey _contentKey = GlobalKey();
  final ScreenCapturer _capturer = ScreenCapturer.instance;
  
  String _originalText = "";
  String _resultText = "DeepSeek 翻译助手\nAlt+Q 划词 | Alt+W 截图"; 
  bool _isLoading = false;
  bool _showOriginal = true;
  late bool _showSettings; 
  
  // 控制器
  final TextEditingController _dsKeyCtrl = TextEditingController();
  final TextEditingController _ocrUrlCtrl = TextEditingController(); // 替换 AK
  final TextEditingController _ocrTokenCtrl = TextEditingController(); // 替换 SK

  bool _isManuallyResized = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    
    _showSettings = widget.isFirstRun;
    if (widget.isFirstRun) _resultText = "";
    
    _initializeApp();
    Future.delayed(Duration.zero, _initSystemTray);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _dsKeyCtrl.dispose();
    _ocrUrlCtrl.dispose();
    _ocrTokenCtrl.dispose();
    super.dispose();
  }

  // --- 初始化逻辑 ---
  void _initializeApp() async {
    await _dsApi.initialize();
    await _ocrApi.initialize(); // 初始化 OCR
    
    bool hasDsKey = _dsApi.hasApiKey();
    if (!widget.isFirstRun && !hasDsKey) {
      setState(() => _showSettings = true);
    }
    
    _dsKeyCtrl.text = await ConfigService.getDeepSeekKey() ?? "";
    
    // 加载 OCR 配置
    final ocrConfig = await ConfigService.getOcrConfig();
    _ocrUrlCtrl.text = ocrConfig['url'] ?? "";
    _ocrTokenCtrl.text = ocrConfig['token'] ?? "";

    _initHotkeys();
  }

  void _initHotkeys() async {
    // 注册前先清理，防止重复
    await hotKeyManager.unregisterAll();
    
    await hotKeyManager.register(
      HotKey(key: PhysicalKeyboardKey.keyQ, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system),
      keyDownHandler: (_) => _handleTextSelection(),
    );

    await hotKeyManager.register(
      HotKey(key: PhysicalKeyboardKey.keyW, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system),
      keyDownHandler: (_) => _handleScreenOCR(),
    );
  }

  // --- 系统托盘 ---
  Future<void> _initSystemTray() async {
    String iconPath = 'assets/app_icon.ico'; 
    try {
      final directory = await getTemporaryDirectory();
      final targetPath = '${directory.path}/tray_icon.ico';
      ByteData data = await rootBundle.load(iconPath);
      File(targetPath).writeAsBytesSync(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      await trayManager.setIcon(targetPath);
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show_window', label: '显示主界面'),
      MenuItem(key: 'settings', label: '设置'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出 Translate_X'),
    ]));
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        windowManager.focus();
        break;
      case 'settings':
        _openSettings();
        break;
      case 'exit_app':
        await trayManager.destroy();
        exit(0);
    }
  }

  // --- 核心功能：截图 OCR ---
  Future<void> _handleScreenOCR() async {
    if (!_ocrApi.hasConfig()) {
      _restoreWindow("未配置 OCR 服务器,请前往设置配置");
      _openSettings(); 
      return;
    }

    await windowManager.hide();
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      // [修改] 不再创建 Directory 和 imagePath
      
      CapturedData? capturedData = await _capturer.capture(
        mode: CaptureMode.region, 
        imagePath: null, // [关键修改] 设为 null，不保存文件，不触发系统通知
      );

      // [修改] 检查 imageBytes 是否存在
      if (capturedData != null && capturedData.imageBytes != null) {
        _startLoadingState("正在识别文字..."); 
        
        // [修改] 直接传入 bytes 数据
        String? ocrText = await _ocrApi.recognizeText(capturedData.imageBytes!);

        if (ocrText != null && ocrText.trim().isNotEmpty && !ocrText.contains("失败") && !ocrText.contains("错误")) {
          _startTranslationFlow(ocrText);
        } else {
          _restoreWindow(ocrText ?? "未识别到文字");
        }
      }
    } catch (e) {
      _restoreWindow("OCR 异常: $e");
    }
  }

  // --- 核心功能：划词翻译 ---
  Future<void> _handleTextSelection() async {
    await windowManager.hide();
    await Future.delayed(const Duration(milliseconds: 100));
    KeyboardSimulator.simulateCopy();
    await Future.delayed(const Duration(milliseconds: 300)); // 等待系统剪贴板
    
    ClipboardData? clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    String text = clipboardData?.text ?? "";
    
    if (text.isNotEmpty) {
      _startTranslationFlow(text);
    }
  }

  // --- 界面状态控制 ---
  
  // 计算窗口位置，确保不超出屏幕
  Future<void> _updateWindowPosition() async {
    Offset mousePos = await screenRetriever.getCursorScreenPoint();
    Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
    Rect bounds = await windowManager.getBounds();
    
    double newX = mousePos.dx + 15;
    double newY = mousePos.dy + 15;
    
    // 右边界检测
    if (newX + bounds.width > primaryDisplay.size.width) {
      newX = mousePos.dx - bounds.width - 15;
    }
    // 下边界检测
    if (newY + bounds.height > primaryDisplay.size.height) {
      newY = mousePos.dy - bounds.height - 15;
    }
    
    // 确保不为负数（左/上边界）
    if (newX < 0) newX = 10;
    if (newY < 0) newY = 10;

    await windowManager.setPosition(Offset(newX, newY));
  }

  Future<void> _startLoadingState(String text) async {
    if (!mounted) return;
    setState(() {
      _showSettings = false;
      _isLoading = true;
      _resultText = text;
      _originalText = "";
    });
    
    await _updateWindowPosition();
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
       await _updateWindowPosition();
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
      // 增加一些底部 Padding 缓冲
      double newHeight = renderBox.size.height + 65; 
      
      // 获取当前屏幕高度，防止窗口过高
      Display display = await screenRetriever.getPrimaryDisplay();
      double maxHeight = display.size.height * 0.8;
      
      newHeight = newHeight.clamp(200, maxHeight);
      
      Rect currentBounds = await windowManager.getBounds();
      await windowManager.setSize(Size(currentBounds.width, newHeight));
    }
  }

  Future<void> _restoreWindow(String? message) async {
    if (!mounted) return;
    await windowManager.show();
    await windowManager.focus();
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message), 
          behavior: SnackBarBehavior.floating, 
          backgroundColor: message.contains("异常") || message.contains("失败") ? Colors.red : Colors.black87
        ),
      );
    }
  }

  void _openSettings() async {
    setState(() => _showSettings = true);
    await windowManager.show();
    await windowManager.focus();
    Rect bounds = await windowManager.getBounds();
    if (bounds.height < 460) {
      await windowManager.setSize(Size(bounds.width, 460));
    }
  }

  Future<void> _saveAllKeys() async {
    final dsKey = _dsKeyCtrl.text.trim();
    final ocrUrl = _ocrUrlCtrl.text.trim();
    final ocrToken = _ocrTokenCtrl.text.trim();

    if (dsKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DeepSeek Key 不能为空'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // 验证 DeepSeek
      _dsApi.setApiKey(dsKey);
      String testTrans = await _dsApi.translate("Hi");
      if (testTrans.contains("配置") || testTrans.contains("失败")) {
        throw "DeepSeek Key 无效，请检查";
      }

      // 保存配置
      if (ocrUrl.isNotEmpty) {
        _ocrApi.setConfig(ocrUrl, ocrToken);
      } else {
        // 如果清空了 URL，也要保存空状态
        await ConfigService.saveOcrConfig("", "");
      }

      await ConfigService.saveDeepSeekKey(dsKey);
      await ConfigService.setNotFirstRun();

      if (!mounted) return;
      
      setState(() {
        _showSettings = false;
        if (_resultText.isEmpty || _resultText.contains("配置") || _resultText.contains("DeepSeek")) {
           _resultText = "配置成功！\nAlt+Q 划词 | Alt+W 截图";
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存'), backgroundColor: Colors.green));
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFitWindowHeight());

    } catch (e) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // --- UI 构建 ---

  Widget _buildTranslationView() {
    return Column(
      key: const ValueKey('translation_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showOriginal && _originalText.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text("原文", style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            child: SelectableText(_originalText, style: const TextStyle(color: Color(0xFF374151), fontSize: 13, height: 1.4)),
          ),
          const SizedBox(height: 16),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(_isLoading ? "翻译中..." : "译文", style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              if (_isLoading) ...[const SizedBox(width: 8), const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))]
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isLoading ? Colors.white : const Color(0xFFEFF6FF), // 浅蓝色背景
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _isLoading ? Colors.grey.shade200 : const Color(0xFFBFDBFE), width: 1),
            boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: SelectableText(
            _resultText, 
            style: const TextStyle(fontSize: 14.5, color: Color(0xFF1E3A8A), height: 1.6, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return Container(
      key: const ValueKey('settings_view'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle("1. 翻译模型配置 (DeepSeek)"),
          const SizedBox(height: 8),
          _buildInput(_dsKeyCtrl, "sk-xxxxxxxxxxxxxxxx", "DeepSeek API Key"),
          
          const SizedBox(height: 24),
          _buildSectionTitle("2. 私有 OCR 服务器 (RapidOCR)"),
          const SizedBox(height: 4),
          Text("仅截图翻译需要。部署教程请参考文档。", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          _buildInput(_ocrUrlCtrl, "http://1.2.3.4:1234", "服务器地址 URL"),
          const SizedBox(height: 10),
          _buildInput(_ocrTokenCtrl, "API Token / 访问密码 (选填)", "Server Token"),

          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isVerifying ? null : () async { 
                  await ConfigService.clearAllKeys(); 
                  _dsApi.setApiKey(""); // 清空内存中的密钥
                  _ocrApi.setConfig("", ""); // 清空内存中的配置
                  setState(() {
                    _dsKeyCtrl.clear(); 
                    _ocrUrlCtrl.clear(); 
                    _ocrTokenCtrl.clear();
                  }); 
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已重置所有配置'), backgroundColor: Colors.orange)
                    );
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                child: const Text("重置"),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isVerifying ? null : _saveAllKeys,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB), 
                  foregroundColor: Colors.white, 
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
                child: _isVerifying
                    ? Row(mainAxisSize: MainAxisSize.min, children: const [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)), SizedBox(width: 8), Text("连接中...")])
                    : const Text("保存并生效", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
      ],
    );
  }

  Widget _buildInput(TextEditingController ctrl, String hint, String label) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400)),
      style: const TextStyle(fontSize: 13, fontFamily: "Monospace"),
      obscureText: label.contains("Key") || label.contains("Token"), // 自动隐藏敏感信息
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: RepaintBoundary( // 性能优化
          child: Container(
            margin: const EdgeInsets.all(12), // 留出阴影空间
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(16), 
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, spreadRadius: 4, offset: const Offset(0, 8)),
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, spreadRadius: 0, offset: const Offset(0, 1)),
              ]
            ),
            child: Column(
              children: [
                // 顶部标题栏
                Container(
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB), 
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)), 
                    border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB)))
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      // 拖拽区域
                      Expanded(
                        child: GestureDetector(
                          onPanDown: (_) => windowManager.startDragging(),
                          behavior: HitTestBehavior.translucent,
                          child: Row(children: [
                            const Icon(Icons.g_translate_rounded, size: 18, color: Color(0xFF2563EB)), 
                            const SizedBox(width: 10), 
                            Text(_showSettings ? "配置中心" : "Translate X", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF374151), fontFamily: "Segoe UI"))
                          ]),
                        ),
                      ),
                      // 按钮区域
                      if (!_showSettings) ...[
                        _HeaderBtn(icon: _showOriginal ? Icons.visibility_outlined : Icons.visibility_off_outlined, tooltip: "显示/隐藏原文", onTap: () { setState(() => _showOriginal = !_showOriginal); WidgetsBinding.instance.addPostFrameCallback((_) => _autoFitWindowHeight()); }),
                        _HeaderBtn(icon: Icons.copy_rounded, tooltip: "复制结果", onTap: () async { await Clipboard.setData(ClipboardData(text: _resultText)); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制译文'), duration: Duration(milliseconds: 800), width: 200, behavior: SnackBarBehavior.floating)); }),
                        _HeaderBtn(icon: Icons.settings_outlined, tooltip: "设置", onTap: _openSettings),
                        Container(width: 1, height: 14, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 10)),
                      ],
                      _HeaderBtn(icon: Icons.close_rounded, tooltip: "隐藏 (Esc)", onTap: () => windowManager.hide(), isClose: true),
                    ],
                  ),
                ),
                
                // 内容区域
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Container(
                      key: _contentKey, 
                      padding: const EdgeInsets.all(20),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250), 
                        switchInCurve: Curves.easeOutQuad,
                        child: _showSettings ? _buildSettingsView() : _buildTranslationView()
                      ),
                    ),
                  ),
                ),
                
                // 底部拖拽手柄
                GestureDetector(
                  onPanDown: (_) { windowManager.startResizing(ResizeEdge.bottomRight); _isManuallyResized = true; },
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    height: 24, 
                    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                    child: Stack(
                      children: [
                        const Center(child: Text("Alt+Q 划词  •  Alt+W 截图", style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500))), 
                        Positioned(right: 8, bottom: 8, child: Icon(Icons.signal_cellular_4_bar, size: 10, color: Colors.grey.shade300))
                      ],
                    )
                  ),
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
  final IconData icon; final VoidCallback onTap; final String tooltip; final bool isClose;
  const _HeaderBtn({required this.icon, required this.onTap, required this.tooltip, this.isClose = false});
  @override
  Widget build(BuildContext context) { 
    return Tooltip(
      message: tooltip, 
      child: Material(
        color: Colors.transparent, 
        child: InkWell(
          onTap: onTap, 
          hoverColor: isClose ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6), 
          child: Padding(
            padding: const EdgeInsets.all(6.0), 
            child: Icon(icon, size: 18, color: isClose ? Colors.red.shade400 : Colors.grey.shade600)
          )
        )
      )
    ); 
  }
}