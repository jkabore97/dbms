# What R8 must not strip when it shrinks the release build.
#
# Flutter's own engine classes and every plugin reached through the method
# channel are looked up by name at runtime, which a shrinker cannot see.
# ML Kit (text recognition, the barcode scanner's engine) loads its models
# and detectors by reflection too. Keeping these whole costs a little of the
# saving and none of the safety: a shrunk build that opens the camera and
# reads nothing is worse than a heavier one that works.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# The barcode scanner (mobile_scanner) and its camera.
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Local storage and the crash reporter register themselves by name.
-keep class com.tekartik.sqflite.** { *; }
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Play Core: Flutter references its deferred-components API even when the
# app has no deferred components, and R8 otherwise fails the build on it.
-dontwarn com.google.android.play.core.**
