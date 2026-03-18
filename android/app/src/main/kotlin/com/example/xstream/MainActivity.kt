package com.example.xstream

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val vpnPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val granted = result.resultCode == Activity.RESULT_OK
            PacketTunnelController.onVpnPermissionResult(this, granted)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.xstream/native"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePacketTunnelProfile" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    result.success(PacketTunnelController.saveProfile(this, args))
                }
                "startPacketTunnel" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(
                        PacketTunnelController.start(this, args) { intent ->
                            vpnPermissionLauncher.launch(intent)
                        }
                    )
                }
                "stopPacketTunnel" -> result.success(PacketTunnelController.stop(this))
                "getPacketTunnelStatus" -> result.success(PacketTunnelController.status(this))
                "openVpnSettings" -> result.success(openVpnSettings())
                "startNodeService", "stopNodeService", "performAction" -> result.success("Android not supported")
                "checkNodeStatus" -> result.success(false)
                else -> result.notImplemented()
            }
        }
    }

    private fun openVpnSettings(): String {
        return try {
            startActivity(
                Intent(Settings.ACTION_VPN_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            "opened"
        } catch (t: Throwable) {
            "failed: ${t.message ?: "unknown_error"}"
        }
    }
}
