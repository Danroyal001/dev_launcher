import 'dart:ffi' show Abi;

/// The Android APK split this build runs on, or '' off Android.
String deviceAbi() => switch (Abi.current()) {
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidX64 => 'x86_64',
      _ => '',
    };
