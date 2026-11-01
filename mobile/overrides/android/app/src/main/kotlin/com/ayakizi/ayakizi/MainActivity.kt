package com.ayakizi.ayakizi

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * "ayakizi/sms" kanalı: bu telefonun SMS gelen kutusunu okur.
 * Mesajlar yalnızca uygulamanın Dart tarafına verilir; ağa gönderilmez.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ayakizi/sms"
    private val permissionRequestCode = 4711
    private var pendingPermission: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasSmsPermission())
                    "requestPermission" -> requestSmsPermission(result)
                    "readInbox" -> {
                        val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                        readInbox(since, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSmsPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "İzin isteği zaten açık", null)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.READ_SMS), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }

    private fun readInbox(sinceMillis: Long, result: MethodChannel.Result) {
        if (!hasSmsPermission()) {
            result.error("permission", "SMS okuma izni yok", null)
            return
        }
        executor.execute {
            try {
                val out = ArrayList<Map<String, Any?>>()
                val selection = if (sinceMillis > 0) "${Telephony.Sms.DATE} >= ?" else null
                val args = if (sinceMillis > 0) arrayOf(sinceMillis.toString()) else null
                contentResolver.query(
                    Telephony.Sms.Inbox.CONTENT_URI,
                    arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
                    selection,
                    args,
                    "${Telephony.Sms.DATE} DESC"
                )?.use { c ->
                    val iAddress = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                    val iBody = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                    val iDate = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
                    while (c.moveToNext()) {
                        out.add(
                            mapOf(
                                "address" to c.getString(iAddress),
                                "body" to c.getString(iBody),
                                "date" to c.getLong(iDate)
                            )
                        )
                    }
                }
                mainHandler.post { result.success(out) }
            } catch (e: Exception) {
                mainHandler.post { result.error("read", e.message, null) }
            }
        }
    }
}
