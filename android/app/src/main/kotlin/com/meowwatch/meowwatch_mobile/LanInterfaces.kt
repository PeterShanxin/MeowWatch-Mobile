package com.meowwatch.meowwatch_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

/** Uses the active route's real prefix; discovery results do not define LAN scope. */
object LanInterfaces {
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "meowwatch/lan_interfaces").setMethodCallHandler { call, result ->
            if (call.method != "listIPv4") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val network = manager.activeNetwork
                val capabilities = network?.let { manager.getNetworkCapabilities(it) }
                val properties = network?.let { manager.getLinkProperties(it) }
                // A VPN can change routing even when Wi-Fi remains connected. Fail closed
                // rather than promise an on-link route we cannot bind from Dart sockets.
                if (capabilities == null || properties == null ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                    !(capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))) {
                    result.error("lan_unavailable", "Connect this device to the same Wi-Fi or Ethernet network as your desktop.", null)
                    return@setMethodCallHandler
                }
                val interfaces = properties.linkAddresses.mapNotNull { link ->
                    val address = link.address
                    if (address !is Inet4Address || link.prefixLength !in 1..30 ||
                        !(address.isSiteLocalAddress || address.isLinkLocalAddress)) {
                        null
                    } else {
                        mapOf(
                            "address" to address.hostAddress,
                            "prefixLength" to link.prefixLength,
                            "interfaceId" to "${network.networkHandle}:${properties.interfaceName}",
                            "friendlyName" to if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) "Wi-Fi" else "Ethernet"
                        )
                    }
                }
                result.success(interfaces)
            } catch (error: SecurityException) {
                result.error("permission_denied", "Android did not allow access to local network information.", null)
            } catch (error: Exception) {
                result.error("lan_unavailable", "Could not read this device's local network.", null)
            }
        }
    }
}
