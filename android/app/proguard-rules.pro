# Keep Kotlin serialization metadata used by Supabase Kotlin.
-keepattributes *Annotation*,InnerClasses,EnclosingMethod
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class **$$serializer { *; }
