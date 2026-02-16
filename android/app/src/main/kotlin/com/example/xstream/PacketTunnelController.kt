package com.example.xstream

import android.content.Context
import android.content.Intent
import android.net.VpnService
import org.json.JSONObject

internal object PacketTunnelController {
    private const val PREFS = "xstream_packet_tunnel"
    private const val KEY_PROFILE = "profile_json"
    private const val KEY_STATE = "state"
    private const val KEY_ERROR = "last_error"
    private const val KEY_STARTED_AT = "started_at"

    private const val STATE_NOT_CONFIGURED = "not_configured"
    private const val STATE_DISCONNECTED = "disconnected"
    private const val STATE_CONNECTING = "connecting"
    private const val STATE_CONNECTED = "connected"
    private const val STATE_INVALID = "invalid"

    fun saveProfile(context: Context, profileMap: Map<*, *>): String {
        val json = JSONObject()
        profileMap.forEach { (key, value) ->
            if (key is String) {
                json.put(key, value)
            }
        }
        prefs(context).edit().putString(KEY_PROFILE, json.toString()).apply()
        clearError(context)
        if (readState(context) == STATE_NOT_CONFIGURED) {
            writeState(context, STATE_DISCONNECTED)
        }
        return "profile_saved"
    }

    fun start(context: Context, profileMap: Map<*, *>?): String {
        if (profileMap != null) {
            saveProfile(context, profileMap)
        }
        val stored = prefs(context).getString(KEY_PROFILE, null)
            ?: return "profile_missing"

        val prepareIntent = VpnService.prepare(context)
        if (prepareIntent != null) {
            writeError(context, "vpn_permission_required")
            writeState(context, STATE_INVALID)
            return "vpn_permission_required"
        }

        writeState(context, STATE_CONNECTING)
        clearError(context)

        val intent = Intent(context, XstreamPacketTunnelService::class.java).apply {
            action = XstreamPacketTunnelService.ACTION_START
            putExtra(XstreamPacketTunnelService.EXTRA_PROFILE_JSON, stored)
        }
        context.startService(intent)
        return "start_submitted"
    }

    fun stop(context: Context): String {
        val intent = Intent(context, XstreamPacketTunnelService::class.java).apply {
            action = XstreamPacketTunnelService.ACTION_STOP
        }
        context.startService(intent)
        writeState(context, STATE_DISCONNECTED)
        clearStartedAt(context)
        return "stop_submitted"
    }

    fun status(context: Context): Map<String, Any?> {
        return mapOf(
            "status" to readState(context),
            "utun" to emptyList<String>(),
            "lastError" to prefs(context).getString(KEY_ERROR, null),
            "startedAt" to prefs(context).getLong(KEY_STARTED_AT, 0L).takeIf { it > 0L },
        )
    }

    fun markConnected(context: Context) {
        writeState(context, STATE_CONNECTED)
        clearError(context)
        prefs(context).edit().putLong(KEY_STARTED_AT, System.currentTimeMillis() / 1000L).apply()
    }

    fun markDisconnected(context: Context) {
        writeState(context, STATE_DISCONNECTED)
        clearStartedAt(context)
    }

    fun markFailed(context: Context, message: String) {
        writeState(context, STATE_INVALID)
        writeError(context, message)
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun writeState(context: Context, state: String) {
        prefs(context).edit().putString(KEY_STATE, state).apply()
    }

    private fun readState(context: Context): String {
        return prefs(context).getString(KEY_STATE, STATE_NOT_CONFIGURED) ?: STATE_NOT_CONFIGURED
    }

    private fun writeError(context: Context, message: String) {
        prefs(context).edit().putString(KEY_ERROR, message).apply()
    }

    private fun clearError(context: Context) {
        prefs(context).edit().remove(KEY_ERROR).apply()
    }

    private fun clearStartedAt(context: Context) {
        prefs(context).edit().remove(KEY_STARTED_AT).apply()
    }
}
