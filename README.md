# Translate X

一个极简、高效的 Windows 桌面翻译工具，集成 DeepSeek 翻译与百度 OCR 截图识别。

![App Icon](assets/app_icon.ico)

## ✨ 功能特点

* **DeepSeek 强力驱动**：利用 DeepSeek API 进行精准、自然的文本翻译。
* **截图 OCR**：按下 `Alt + W` 即可截图识别屏幕文字（由百度智能云 OCR 支持）。
* **划词翻译**：选中任意文本，按下 `Alt + Q` 立即翻译。
* **极简设计**：无边框窗口，自动适应内容高度，支持拖拽调整大小。
* **托盘常驻**：最小化至系统托盘，右键菜单快速控制。

## 🛠️ 技术栈

* **Flutter** (Windows Desktop)
* **window_manager**: 窗口管理
* **tray_manager**: 系统托盘
* **screen_capturer**: 屏幕截图
* **hotkey_manager**: 全局快捷键

## 🚀 如何使用

1. 下载 Release 版本并解压。
2. 运行 `translate_x.exe`。
3. 首次运行会自动打开**配置中心**。
4. 填入 **DeepSeek API Key** (必填)。
5. (可选) 填入 **百度 OCR AK/SK** 以启用截图翻译功能。
6. 点击保存，即可开始使用！

## ⌨️ 快捷键

* `Alt + Q`: 翻译选中的文本
* `Alt + W`: 截图并翻译
* `Esc`: 隐藏窗口（在窗口激活时）

## 📦 开发者构建

1. 确保安装了 Flutter SDK 和 Visual Studio (C++环境)。
2. 克隆仓库:
   ```bash
   git clone [https://github.com/你的用户名/你的仓库名.git](https://github.com/你的用户名/你的仓库名.git)
