package com.example.xstream

internal object NativePacketTunnelBridge {
    private val loaded: Boolean = try {
        System.loadLibrary("packet_tunnel_jni")
        true
    } catch (_: Throwable) {
        false
    }

    fun isAvailable(): Boolean = loaded

    fun startTunnel(configJson: String, tunFd: Int): Long {
        if (!loaded) {
            return -1L
        }
        if (configJson.isBlank() || tunFd <= 0) {
            return -1L
        }
        return nativeStartTunnel(configJson, tunFd)
    }

    fun stopTunnel(handle: Long): String {
        if (!loaded || handle <= 0L) {
            return "error:not_available"
        }
        return nativeStopTunnel(handle)
    }

    fun freeTunnel(handle: Long): String {
        if (!loaded || handle <= 0L) {
            return "error:not_available"
        }
        return nativeFreeTunnel(handle)
    }

    private external fun nativeStartTunnel(configJson: String, tunFd: Int): Long
    private external fun nativeStopTunnel(handle: Long): String
    private external fun nativeFreeTunnel(handle: Long): String
}
