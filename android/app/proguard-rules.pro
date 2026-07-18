# Meta Audience Network ProGuard Rules
-keep class com.facebook.ads.** { *; }
-dontwarn com.facebook.infer.annotation.**

# AdMob ProGuard Rules (Basic)
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.mediation.** { *; }
