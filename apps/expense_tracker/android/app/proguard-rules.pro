# Release builds are shrunk by R8. WorkManager (BackupWorker.kt) opens its
# own Room database on start, and Room finds the generated WorkDatabase_Impl
# by name: without these rules R8 removed or renamed it, and the app
# stopped as it opened ("Failed to create an instance of ... WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keepnames class androidx.work.impl.WorkDatabase
# WorkManager makes each worker by name with this constructor.
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
