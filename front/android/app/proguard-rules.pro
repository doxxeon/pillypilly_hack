##########################################
# 🧠 Flutter & Dart 기본 설정
##########################################
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Dart FFI (네이티브 코드)
-keep class * extends java.lang.Enum
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

##########################################
# 🔍 Google ML Kit (Text Recognition 등)
##########################################
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# ✅ 언어별 OCR 모델 보호
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-keep class com.google.mlkit.vision.text.latin.** { *; }

##########################################
# 🧩 SnakeYAML / dotenv 관련 (환경변수 로딩)
##########################################
-keep class org.yaml.snakeyaml.** { *; }
-dontwarn org.yaml.snakeyaml.**
-keep class java.beans.** { *; }
-dontwarn java.beans.**

##########################################
# 🧱 Retrofit / Dio / JSON 관련 (만약 사용 중이라면)
##########################################
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keepclassmembers class * {
    @retrofit2.http.* <methods>;
}
-dontwarn okhttp3.**
-dontwarn retrofit2.**
-dontwarn okio.**

##########################################
# 🗣️ Text-To-Speech 관련
##########################################
-keep class android.speech.tts.** { *; }
-dontwarn android.speech.tts.**

##########################################
# 🧰 Kotlin 메타데이터 유지
##########################################
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

##########################################
# 🧩 Firebase (만약 사용 시)
##########################################
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

##########################################
# 🧩 MLKit Common Model Parser (Image 등)
##########################################
-keep class com.google.mlkit.vision.common.internal.VisionCommonRegistrar { *; }
-keep class com.google.mlkit.vision.text.internal.TextRegistrar { *; }

##########################################
# 🚫 경고 억제
##########################################
-dontnote
-dontwarn org.apache.commons.**
-dontwarn javax.annotation.**