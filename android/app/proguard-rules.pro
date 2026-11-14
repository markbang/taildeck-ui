# AGP 9 minifies release builds by default. Classes below are looked up from
# native code by name (Go JNI GetMethodID, package:jni), so shrinking would
# delete the members the app is started with.
-keep class top.bangwu.taildeck.PlatformBridge { *; }
