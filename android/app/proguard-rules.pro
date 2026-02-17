# --- FLUTTER WRAPPER ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- GOOGLE PLAY CORE FIX (CRITICAL FOR YOUR BUILD ERROR) ---
# This ignores the missing classes related to Split Install that caused the R8 failure
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# --- LIBBOX / SINGBOX / SAGERNET ---
# Protects the new library structure
-keep class io.nekohasekai.libbox.** { *; }
-keep interface io.nekohasekai.libbox.** { *; }
# Protects older references just in case
-keep class io.github.nekohasekai.libbox.** { *; }
-keep interface io.github.nekohasekai.libbox.** { *; }
-keep class io.github.sagernet.** { *; }
-keep class io.github.sagernet.libbox.** { *; }

# --- GENERAL SAFETY ---
-dontwarn **
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
