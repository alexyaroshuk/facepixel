package com.facepixel.app.facedetection

import android.graphics.Bitmap
import android.graphics.YuvImage
import android.util.Log
import android.graphics.Rect as GraphicsRect
import java.io.ByteArrayOutputStream

class FrameBuffer {
    private val tag = "FrameBuffer"
    private var cachedBitmap: Bitmap? = null
    private var lastWidth = 0
    private var lastHeight = 0
    private var conversionCount = 0

    fun convertNV21ToBitmap(nv21Bytes: ByteArray, width: Int, height: Int): Bitmap {
        // Reuse bitmap if size matches, otherwise create new one
        if (cachedBitmap == null || lastWidth != width || lastHeight != height) {
            cachedBitmap?.recycle()
            cachedBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            lastWidth = width
            lastHeight = height
            Log.d(tag, "Created new bitmap: ${width}x${height}")
        }

        val bitmap = cachedBitmap!!
        try {
            // Convert NV21 directly to bitmap
            decodeNV21ToARGB8888(nv21Bytes, width, height, bitmap)

            if (conversionCount++ % 10 == 0) {
                Log.d(tag, "Converted frame #${conversionCount}: ${width}x${height}")
            }

            return bitmap
        } catch (e: Exception) {
            Log.e(tag, "Error converting NV21 to bitmap: ${e.message}", e)
            return bitmap
        }
    }

    private fun decodeNV21ToARGB8888(nv21: ByteArray, width: Int, height: Int, bitmap: Bitmap) {
        val pixels = IntArray(width * height)

        // NV21 format: Y plane + VU plane (interleaved)
        // Y: 0 to width*height-1
        // VU: width*height to width*height + width*height/2-1 (V at even indices, U at odd)
        val yPlaneSize = width * height

        for (y in 0 until height) {
            for (x in 0 until width) {
                val yIndex = y * width + x

                // UV indices - NV21 is VU interleaved
                val uvx = x / 2
                val uvy = y / 2
                val uvIndex = yPlaneSize + uvy * width + uvx * 2

                val yVal = nv21[yIndex].toInt() and 0xFF
                val v = (nv21[uvIndex].toInt() and 0xFF) - 128        // V (red)
                val u = (nv21[uvIndex + 1].toInt() and 0xFF) - 128    // U (blue)

                // YUV to RGB conversion
                val r = (yVal + 1.402 * v).toInt().coerceIn(0, 255)
                val g = (yVal - 0.344136 * u - 0.714136 * v).toInt().coerceIn(0, 255)
                val b = (yVal + 1.772 * u).toInt().coerceIn(0, 255)

                // ARGB8888 format: alpha | red | green | blue
                pixels[y * width + x] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }

        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }

    fun release() {
        cachedBitmap?.recycle()
        cachedBitmap = null
    }
}
