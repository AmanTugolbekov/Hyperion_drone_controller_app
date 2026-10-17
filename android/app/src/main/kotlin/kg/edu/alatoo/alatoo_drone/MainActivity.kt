package kg.edu.alatoo.alatoo_drone

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Pins the app's sockets to the Wi-Fi network.
 *
 * A drone's access point has no internet, so Android treats it as a dead
 * network and silently routes every socket over mobile data instead — the
 * control packets then leave the phone and never reach the drone. Binding the
 * process to the Wi-Fi network overrides that routing decision.
 */
class MainActivity : FlutterActivity() {

    private val channel = "kg.edu.alatoo.alatoo_drone/network"

    private var connectivity: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        connectivity =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "bindToWifi" -> bindToWifi(result)
                "unbind" -> {
                    unbind()
                    result.success(true)
                }
                "isBound" -> result.success(
                    connectivity?.boundNetworkForProcess != null,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun bindToWifi(result: MethodChannel.Result) {
        val manager = connectivity
        if (manager == null) {
            result.success(false)
            return
        }

        unbind()

        // NET_CAPABILITY_INTERNET is deliberately left out: the drone's access
        // point does not provide it, and requiring it would never match.
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        // Guards against the callback firing twice, which would otherwise
        // reply on an already-completed Flutter result and crash the channel.
        var replied = false

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val ok = manager.bindProcessToNetwork(network)
                if (!replied) {
                    replied = true
                    runOnUiThread { result.success(ok) }
                }
            }

            override fun onUnavailable() {
                if (!replied) {
                    replied = true
                    runOnUiThread { result.success(false) }
                }
            }
        }

        callback = cb
        try {
            manager.requestNetwork(request, cb, BIND_TIMEOUT_MS)
        } catch (e: SecurityException) {
            // CHANGE_NETWORK_STATE missing or refused by the OEM build.
            callback = null
            result.success(false)
        }
    }

    private fun unbind() {
        val manager = connectivity ?: return
        manager.bindProcessToNetwork(null)
        callback?.let {
            try {
                manager.unregisterNetworkCallback(it)
            } catch (e: IllegalArgumentException) {
                // Already unregistered; nothing to undo.
            }
        }
        callback = null
    }

    override fun onDestroy() {
        unbind()
        super.onDestroy()
    }

    companion object {
        private const val BIND_TIMEOUT_MS = 8000
    }
}
