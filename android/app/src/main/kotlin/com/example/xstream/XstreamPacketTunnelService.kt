package com.example.xstream

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.InetAddress

class XstreamPacketTunnelService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var tunnelHandle: Long = 0L

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startTunnel(intent.getStringExtra(EXTRA_PROFILE_JSON))
            ACTION_STOP -> {
                stopTunnel()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    private fun startTunnel(profileJson: String?) {
        if (profileJson.isNullOrBlank()) {
            PacketTunnelController.markFailed(this, "profile_missing")
            stopSelf()
            return
        }

        try {
            val profile = JSONObject(profileJson)
            val mtu = profile.optInt("mtu", 1500).coerceIn(1200, 9000)
            val dns4 = jsonStringArray(profile.optJSONArray("dnsServers4"))
            val dns6 = jsonStringArray(profile.optJSONArray("dnsServers6"))
            val ipv4Addresses = jsonStringArray(profile.optJSONArray("ipv4Addresses"))
            val ipv4SubnetMasks = jsonStringArray(profile.optJSONArray("ipv4SubnetMasks"))
            val ipv4Routes = profile.optJSONArray("ipv4IncludedRoutes")
            val ipv6Addresses = jsonStringArray(profile.optJSONArray("ipv6Addresses"))
            val ipv6Prefixes = jsonIntArray(profile.optJSONArray("ipv6NetworkPrefixLengths"))
            val ipv6Routes = profile.optJSONArray("ipv6IncludedRoutes")

            val baseConfig = resolveConfigJson(profile)
            if (baseConfig.isNullOrBlank()) {
                PacketTunnelController.markFailed(this, "config_missing")
                stopSelf()
                return
            }
            val tunnelConfig = ensureTunInbound(baseConfig, mtu)

            stopTunnel()

            val builder = Builder()
                .setSession("Xstream Secure Tunnel")
                .setMtu(mtu)

            val ipv4Address = ipv4Addresses.firstOrNull() ?: "10.0.0.2"
            val ipv4Mask = ipv4SubnetMasks.firstOrNull() ?: "255.255.255.0"
            builder.addAddress(ipv4Address, maskToPrefixLength(ipv4Mask))

            val ipv6Address = ipv6Addresses.firstOrNull()
            val ipv6Prefix = ipv6Prefixes.firstOrNull() ?: 120
            if (!ipv6Address.isNullOrBlank()) {
                builder.addAddress(ipv6Address, ipv6Prefix.coerceIn(0, 128))
            }

            addIpv4Routes(builder, ipv4Routes)
            addIpv6Routes(builder, ipv6Routes)

            dns4.forEach { dns ->
                if (dns.isNotBlank()) {
                    builder.addDnsServer(dns)
                }
            }
            dns6.forEach { dns ->
                if (dns.isNotBlank()) {
                    builder.addDnsServer(dns)
                }
            }

            tunInterface = builder.establish()
            val tunFd = tunInterface?.fd ?: -1
            if (tunFd <= 0) {
                PacketTunnelController.markFailed(this, "establish_failed")
                stopSelf()
                return
            }

            if (!NativePacketTunnelBridge.isAvailable()) {
                PacketTunnelController.markFailed(this, "native_bridge_unavailable")
                stopTunnel(markDisconnected = false)
                stopSelf()
                return
            }

            tunnelHandle = NativePacketTunnelBridge.startTunnel(tunnelConfig, tunFd)
            if (tunnelHandle <= 0L) {
                PacketTunnelController.markFailed(this, "xray_start_failed")
                stopTunnel(markDisconnected = false)
                stopSelf()
                return
            }

            PacketTunnelController.markConnected(this)
        } catch (t: Throwable) {
            PacketTunnelController.markFailed(this, t.message ?: "start_failed")
            stopTunnel(markDisconnected = false)
            stopSelf()
        }
    }

    private fun stopTunnel(markDisconnected: Boolean = true) {
        if (tunnelHandle > 0L) {
            try {
                NativePacketTunnelBridge.stopTunnel(tunnelHandle)
            } catch (_: Throwable) {
            }
            try {
                NativePacketTunnelBridge.freeTunnel(tunnelHandle)
            } catch (_: Throwable) {
            }
            tunnelHandle = 0L
        }

        try {
            tunInterface?.close()
        } catch (_: Throwable) {
        } finally {
            tunInterface = null
        }

        if (markDisconnected) {
            PacketTunnelController.markDisconnected(this)
        }
    }

    private fun resolveConfigJson(profile: JSONObject): String? {
        val inlineConfig = profile.optString("configJson", "").trim()
        if (inlineConfig.isNotEmpty()) {
            return inlineConfig
        }

        val configPath = profile.optString("configPath", "").trim()
        if (configPath.isEmpty()) {
            return null
        }
        val file = File(configPath)
        if (!file.exists() || !file.isFile) {
            return null
        }
        return file.readText()
    }

    private fun ensureTunInbound(configJson: String, mtu: Int): String {
        val root = JSONObject(configJson)
        val inbounds = root.optJSONArray("inbounds") ?: JSONArray()

        var hasTunInbound = false
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.optJSONObject(i) ?: continue
            if (inbound.optString("protocol") == "tun") {
                val settings = inbound.optJSONObject("settings") ?: JSONObject()
                settings.put("name", settings.optString("name", "xray0"))
                settings.put("MTU", settings.optInt("MTU", mtu))
                inbound.put("settings", settings)
                hasTunInbound = true
                break
            }
        }

        if (!hasTunInbound) {
            val tunInbound = JSONObject()
                .put("port", 0)
                .put("protocol", "tun")
                .put("tag", "tun-in")
                .put(
                    "settings",
                    JSONObject()
                        .put("name", "xray0")
                        .put("MTU", mtu)
                        .put("userLevel", 0)
                )
            inbounds.put(tunInbound)
            root.put("inbounds", inbounds)
        }

        return root.toString()
    }

    private fun addIpv4Routes(builder: Builder, routes: JSONArray?) {
        var added = false
        if (routes != null) {
            for (i in 0 until routes.length()) {
                val route = routes.optJSONObject(i) ?: continue
                val destination = route.optString("destinationAddress", "")
                val subnetMask = route.optString("subnetMask", "")
                if (destination.isBlank() || subnetMask.isBlank()) {
                    continue
                }
                try {
                    builder.addRoute(destination, maskToPrefixLength(subnetMask))
                    added = true
                } catch (_: Throwable) {
                }
            }
        }
        if (!added) {
            builder.addRoute("0.0.0.0", 0)
        }
    }

    private fun addIpv6Routes(builder: Builder, routes: JSONArray?) {
        var added = false
        if (routes != null) {
            for (i in 0 until routes.length()) {
                val route = routes.optJSONObject(i) ?: continue
                val destination = route.optString("destinationAddress", "")
                val prefixLength = route.optInt("networkPrefixLength", 0)
                if (destination.isBlank()) {
                    continue
                }
                try {
                    builder.addRoute(destination, prefixLength.coerceIn(0, 128))
                    added = true
                } catch (_: Throwable) {
                }
            }
        }
        if (!added) {
            try {
                builder.addRoute("::", 0)
            } catch (_: Throwable) {
            }
        }
    }

    private fun maskToPrefixLength(mask: String): Int {
        return try {
            val bytes = InetAddress.getByName(mask).address
            bytes.sumOf { byte ->
                Integer.bitCount(byte.toInt() and 0xFF)
            }
        } catch (_: Throwable) {
            24
        }
    }

    private fun jsonStringArray(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        val out = ArrayList<String>(array.length())
        for (i in 0 until array.length()) {
            out.add(array.optString(i, ""))
        }
        return out
    }

    private fun jsonIntArray(array: JSONArray?): List<Int> {
        if (array == null) return emptyList()
        val out = ArrayList<Int>(array.length())
        for (i in 0 until array.length()) {
            out.add(array.optInt(i, 0))
        }
        return out
    }

    companion object {
        const val ACTION_START = "com.xstream.securetunnel.START"
        const val ACTION_STOP = "com.xstream.securetunnel.STOP"
        const val EXTRA_PROFILE_JSON = "profile_json"
    }
}
