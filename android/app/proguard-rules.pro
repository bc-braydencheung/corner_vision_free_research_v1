# Room instantiates its generated *_Impl databases reflectively, so R8 must not
# strip their no-arg constructors. Without this the release build crashes on
# startup in WorkManager's initializer (NoSuchMethodException:
# androidx.work.impl.WorkDatabase_Impl.<init>).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.RoomDatabase$* { *; }
-dontwarn androidx.room.paging.**

# WorkManager loads workers and its initializer by name.
-keep class * extends androidx.work.Worker { <init>(...); }
-keep class * extends androidx.work.InputMerger { <init>(...); }
-keep class androidx.work.impl.** { *; }
-keep class * extends androidx.startup.Initializer { <init>(); }
