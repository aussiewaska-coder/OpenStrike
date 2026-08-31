package com.openstrike.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class OpenStrikeLocationPlugin(godot: Godot) : GodotPlugin(godot), LocationListener {
    companion object {
        private const val REQUEST_LOCATION = 7401
        private const val MIN_UPDATE_TIME_MS = 2_000L
        private const val MIN_UPDATE_DISTANCE_M = 5.0f
    }

    @Volatile private var lastLocation: Location? = null
    @Volatile private var status = "idle"
    private var locationManager: LocationManager? = null

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    @UsedByGodot
    fun hasLocationPermission(): Boolean {
        val host = activity ?: return false
        return host.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            host.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    @UsedByGodot
    fun requestLocationPermission() {
        runOnHostThread {
            val host = activity ?: return@runOnHostThread
            if (hasLocationPermission()) {
                status = "permission_granted"
                startLocationUpdates()
                return@runOnHostThread
            }
            status = "permission_requested"
            host.requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                ),
                REQUEST_LOCATION,
            )
        }
    }

    @SuppressLint("MissingPermission")
    @UsedByGodot
    fun startLocationUpdates() {
        runOnHostThread {
            val host = activity ?: return@runOnHostThread
            if (!hasLocationPermission()) {
                status = "permission_denied"
                return@runOnHostThread
            }
            val manager = host.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            locationManager = manager
            status = "locating"
            val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            providers.forEach { provider ->
                if (manager.allProviders.contains(provider) && manager.isProviderEnabled(provider)) {
                    manager.getLastKnownLocation(provider)?.let(::acceptIfBetter)
                    manager.requestLocationUpdates(
                        provider,
                        MIN_UPDATE_TIME_MS,
                        MIN_UPDATE_DISTANCE_M,
                        this,
                    )
                }
            }
            if (lastLocation != null) status = "location_ready"
        }
    }

    @UsedByGodot
    fun stopLocationUpdates() {
        runOnHostThread {
            locationManager?.removeUpdates(this)
            locationManager = null
            status = if (lastLocation == null) "stopped" else "location_ready"
        }
    }

    @UsedByGodot
    fun getStatus(): String = status

    @UsedByGodot
    fun getLastLatitude(): Double = lastLocation?.latitude ?: 0.0

    @UsedByGodot
    fun getLastLongitude(): Double = lastLocation?.longitude ?: 0.0

    @UsedByGodot
    fun getLastAccuracyMeters(): Double = lastLocation?.accuracy?.toDouble() ?: -1.0

    @UsedByGodot
    fun getLastTimestampMillis(): Long = lastLocation?.time ?: 0L

    override fun onMainRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onMainRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_LOCATION) return
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            status = "permission_granted"
            startLocationUpdates()
        } else {
            status = "permission_denied"
        }
    }

    override fun onMainPause() {
        super.onMainPause()
        locationManager?.removeUpdates(this)
        locationManager = null
    }

    override fun onMainDestroy() {
        locationManager?.removeUpdates(this)
        locationManager = null
        super.onMainDestroy()
    }

    override fun onLocationChanged(location: Location) {
        acceptIfBetter(location)
        status = "location_ready"
    }

    @Deprecated("Deprecated by Android")
    override fun onStatusChanged(provider: String?, state: Int, extras: Bundle?) = Unit

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) {
        if (locationManager?.allProviders?.none { locationManager?.isProviderEnabled(it) == true } == true) {
            status = "providers_disabled"
        }
    }

    private fun acceptIfBetter(candidate: Location) {
        val current = lastLocation
        if (current == null || candidate.time > current.time || candidate.accuracy < current.accuracy) {
            lastLocation = Location(candidate)
        }
    }
}
