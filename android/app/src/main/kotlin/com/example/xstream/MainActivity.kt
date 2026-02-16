package com.example.xstream

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    result.success(PacketTunnelController.start(this, args))
                }
                "stopPacketTunnel" -> result.success(PacketTunnelController.stop(this))
                "getPacketTunnelStatus" -> result.success(PacketTunnelController.status(this))
                "startNodeService", "stopNodeService", "performAction" -> result.success("Android not supported")
                "checkNodeStatus" -> result.success(false)
                else -> result.notImplemented()
            }
        }
    }
}
