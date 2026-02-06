import 'dart:ffi';
import 'dart:io';

class FFILoader {
  static DynamicLibrary? _lib;

  static DynamicLibrary get lib {
    if (_lib != null) return _lib!;
    
    if (Platform.isAndroid) {
      // Standard Android path for JNI libs
      _lib = DynamicLibrary.open("libbox.so");
    } else if (Platform.isWindows) {
      // For Windows, we might use a DLL or stay with process-based execution.
      // Current implementation uses sing-box.exe process.
      // If we had a sing-box.dll:
      // _lib = DynamicLibrary.open("sing-box.dll");
      throw UnsupportedError("FFI not implemented for Windows yet. Use Process-based service.");
    } else {
      _lib = DynamicLibrary.process();
    }
    
    return _lib!;
  }
}
