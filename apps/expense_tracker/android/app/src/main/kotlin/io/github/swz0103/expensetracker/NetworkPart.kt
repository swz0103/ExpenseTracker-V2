package io.github.swz0103.expensetracker

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Whether the phone is on a network that costs nothing per byte, such as
 * Wi-Fi, so large uploads wait for one (lib/src/app/android/network.dart).
 */
class NetworkPart(private val activity: FragmentActivity) : ChannelPart {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "unmetered") return false
        val manager = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
        result.success(
            capabilities != null &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
        )
        return true
    }
}
