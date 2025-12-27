package com.facepixel.app

import android.util.Log

/**
 * Professional logging utility for FacePixel
 * Logs are only shown in debug builds
 */
object AppLogger {
    private const val PREFIX = "FacePixel"

    fun info(message: String, tag: String = "App") {
        if (BuildConfig.DEBUG) {
            Log.i("$PREFIX:$tag", message)
        }
    }

    fun debug(message: String, tag: String = "App") {
        if (BuildConfig.DEBUG) {
            Log.d("$PREFIX:$tag", message)
        }
    }

    fun warn(message: String, tag: String = "App") {
        if (BuildConfig.DEBUG) {
            Log.w("$PREFIX:$tag", message)
        }
    }

    fun error(message: String, tag: String = "App", throwable: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            Log.e("$PREFIX:$tag", message, throwable)
        }
    }
}
