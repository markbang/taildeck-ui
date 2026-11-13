package top.bangwu.taildeck

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetAddress
import java.net.NetworkInterface

/**
 * Android's network APIs for the Go tsnet node. Android 11+ blocks Go's
 * netlink access and there is no resolv.conf, so interfaces, the default
 * interface and DNS lookups come from here through the JNI shim in
 * native/bridge/cmd/cshared/platform_jni.c.
 */
object PlatformBridge {
    private const val TAG = "TaildeckPlatform"

    private var manager: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var loaded = false

    /** Loads the shared lib, hands the JVM to Go and watches the network. */
    fun register(context: Context): Boolean {
        val app = context.applicationContext ?: return false
        if (!loaded) {
            try {
                System.loadLibrary("taildeck_bridge")
                loaded = true
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "libtaildeck_bridge.so unavailable: ${e.message}")
                return false
            }
        }
        val attached = try {
            nativeAttach()
        } catch (e: Throwable) {
            Log.w(TAG, "JNI attach failed: ${e.message}")
            false
        }
        if (attached) watchNetwork(app)
        return attached
    }

    private fun watchNetwork(context: Context) {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        manager = cm
        if (callback != null) return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = notifyChanged()

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = notifyChanged()

            override fun onLost(network: Network) = notifyChanged()
        }
        try {
            cm.registerDefaultNetworkCallback(cb)
            callback = cb
        } catch (e: Exception) {
            Log.w(TAG, "default network callback: ${e.message}")
        }
    }

    private fun notifyChanged() {
        try {
            nativeNetworkChanged()
        } catch (e: Throwable) {
            Log.w(TAG, "network change: ${e.message}")
        }
    }

    /** JSON array of {name,index,mtu,up,loopback,addrs:["ip/bits"]}. */
    @JvmStatic
    fun interfacesJson(): String {
        val array = JSONArray()
        val list = runCatching { NetworkInterface.getNetworkInterfaces()?.toList() }
            .getOrNull()
            .orEmpty()
        for (nif in list) {
            // An interface can vanish between the listing and the reads.
            val item = runCatching { interfaceJson(nif) }.getOrNull() ?: continue
            array.put(item)
        }
        return array.toString()
    }

    private fun interfaceJson(nif: NetworkInterface): JSONObject {
        val addrs = JSONArray()
        nif.interfaceAddresses.forEach { ia ->
            val host = ia.address?.hostAddress?.substringBefore('%') ?: return@forEach
            addrs.put("$host/${ia.networkPrefixLength}")
        }
        return JSONObject()
            .put("name", nif.name)
            .put("index", nif.index)
            .put("mtu", nif.mtu)
            .put("up", nif.isUp)
            .put("loopback", nif.isLoopback)
            .put("addrs", addrs)
    }

    @JvmStatic
    fun defaultInterface(): String = manager?.let { cm ->
        runCatching { cm.getLinkProperties(cm.activeNetwork)?.interfaceName }.getOrNull()
    }.orEmpty()

    @JvmStatic
    fun lookup(host: String): String = try {
        InetAddress.getAllByName(host).joinToString(",") { it.hostAddress?.substringBefore('%') ?: "" }
    } catch (e: Exception) {
        ""
    }

    external fun nativeAttach(): Boolean

    external fun nativeNetworkChanged()
}
