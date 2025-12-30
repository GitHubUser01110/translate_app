import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class KeyboardSimulator {
  static void simulateCopy() {
    final inputs = calloc<INPUT>(5);

    // 0. 抬起 Alt 键
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_MENU;
    inputs[0].ki.dwFlags = KEYEVENTF_KEYUP;

    // 1. 按下 Ctrl
    inputs[1].type = INPUT_KEYBOARD;
    inputs[1].ki.wVk = VK_CONTROL;
    inputs[1].ki.dwFlags = 0;

    // 2. 按下 C
    inputs[2].type = INPUT_KEYBOARD;
    inputs[2].ki.wVk = 0x43; // C 键
    inputs[2].ki.dwFlags = 0;

    // 3. 抬起 C
    inputs[3].type = INPUT_KEYBOARD;
    inputs[3].ki.wVk = 0x43;
    inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

    // 4. 抬起 Ctrl
    inputs[4].type = INPUT_KEYBOARD;
    inputs[4].ki.wVk = VK_CONTROL;
    inputs[4].ki.dwFlags = KEYEVENTF_KEYUP;

    SendInput(5, inputs, sizeOf<INPUT>());
    calloc.free(inputs);
  }
}