// The processor this build runs on, as Android names the APK split for it:
// armeabi-v7a (32-bit ARM, the owner's Tecno), arm64-v8a or x86_64. Empty in
// a browser and on anything else.
export 'device_abi_stub.dart' if (dart.library.ffi) 'device_abi_ffi.dart';
