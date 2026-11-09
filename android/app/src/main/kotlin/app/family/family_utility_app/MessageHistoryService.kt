package app.family.family_utility_app

import android.app.Notification
import android.content.Context
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/// 129 Recover deleted messages: keeps WhatsApp message notifications (and,
/// if asked, copies new WhatsApp media) into the app's own folder so a
/// message the sender deletes can still be read. Opt-in: nothing is written
/// unless the Dart side has created the "enabled" flag file. Nothing leaves
/// the phone.
class MessageHistoryService : NotificationListenerService() {
    private val watched = setOf("com.whatsapp", "com.whatsapp.w4b")

    private val mediaFolders = listOf(
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video",
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes",
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Images",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Video"
    )

    private fun root(): File = File(getDir("flutter", Context.MODE_PRIVATE), "message_history")

    @Suppress("DEPRECATION")
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        if (!watched.contains(n.packageName)) {
            return
        }
        val root = root()
        if (!File(root, "enabled").exists()) {
            return
        }
        try {
            val notification = n.notification
            if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) {
                return
            }
            val extras = notification.extras
            val obj = JSONObject()
            obj.put("app", n.packageName)
            obj.put("title", extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: "")
            obj.put("conversation", extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString() ?: "")
            obj.put("text", extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: "")
            obj.put("posted", n.postTime)
            val messages = JSONArray()
            val raw: Array<Parcelable>? = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (raw != null) {
                for (p in raw) {
                    val b = p as? Bundle ?: continue
                    val m = JSONObject()
                    m.put("text", b.getCharSequence("text")?.toString() ?: "")
                    m.put("time", b.getLong("time"))
                    m.put("sender", b.getCharSequence("sender")?.toString() ?: "")
                    messages.put(m)
                }
            }
            obj.put("messages", messages)
            root.mkdirs()
            File(root, "inbox.jsonl").appendText(obj.toString() + "\n")
            if (File(root, "rescue_media").exists()) {
                rescueMedia(root)
            }
        } catch (e: Exception) {
            // A notification we cannot read is skipped; the next one still counts.
        }
    }

    /// Copies media WhatsApp saved in the last 15 minutes, before the sender
    /// can delete it, into message_history/media.
    private fun rescueMedia(root: File) {
        val target = File(root, "media")
        target.mkdirs()
        val since = System.currentTimeMillis() - 15 * 60 * 1000L
        for (path in mediaFolders) {
            val dir = File(path)
            val files = dir.listFiles() ?: continue
            for (f in files) {
                try {
                    if (!f.isFile || f.name.startsWith(".") || f.lastModified() < since) {
                        continue
                    }
                    if (f.length() <= 0L || f.length() > 100L * 1024L * 1024L) {
                        continue
                    }
                    val out = File(target, f.name)
                    if (!out.exists()) {
                        f.copyTo(out)
                        out.setLastModified(f.lastModified())
                    }
                } catch (e: Exception) {
                    // Deleted or unreadable; skip it.
                }
            }
        }
    }
}
