# Keep Kotlin serialization metadata used by Supabase Kotlin.
-keepattributes *Annotation*,InnerClasses,EnclosingMethod
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class **$$serializer { *; }

# Supabase Kotlin SDK / Ktor transport and reflection-based serialization.
-keepattributes Signature,RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-keep class kotlinx.serialization.** { *; }
-keep @kotlinx.serialization.Serializable class ** { *; }
-keepclassmembers class **$$serializer { *; }
-keepclassmembers class ** {
    *** Companion;
}
# ML Kit barcode scanner and CameraX metadata.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class androidx.camera.** { *; }
# Room rules are included for the future local Room cache module.
-keep class androidx.room.** { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-dontwarn javax.annotation.**
# java.lang.management is part of the desktop JVM, not Android. Ktor references
# these classes only in its optional IntelliJ debugger-detection helper.
-dontwarn java.lang.management.**
