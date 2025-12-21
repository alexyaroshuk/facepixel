package com.facepixel.app.facedetection

import android.util.Log
import java.util.concurrent.Executors

class CameraFrameProcessor(
    private val faceDetector: FaceDetector
) {
    private val tag = "FaceProcessor"
    private var pixelationEnabled = false
    private var pixelationLevel = 50
    private var lastProcessingTime = 0L
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    fun processFrame(
        nv21Bytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int = 0
    ): ProcessingResult {
        val startTime = System.currentTimeMillis()

        Log.d(tag, "┌─ PROCESS FRAME START")
        Log.d(tag, "│ INPUT: ${width}x$height, NV21=${nv21Bytes.size}b, rotation=$rotation°")

        return try {
            // Pass NV21 bytes directly to ML Kit (more efficient than bitmap conversion)
            Log.d(tag, "│ → ML KIT: ${width}x$height")

            val result = object : Any() {
                var faces: List<RectData>? = null
                var error: String? = null
            }

            // Execute on background thread and wait
            val future = backgroundExecutor.submit {
                try {
                    Log.d(tag, "ML KIT PROCESSING: Starting detection on NV21 ${width}x${height}, rotation=$rotation")
                    result.faces = faceDetector.detectFaces(nv21Bytes, width, height, rotation)
                    Log.d(tag, "ML KIT RESULT: Detected ${result.faces?.size ?: 0} faces")
                } catch (e: Exception) {
                    result.error = e.message
                    Log.e(tag, "Background face detection error: ${e.message}", e)
                }
            }

            // Wait for completion (with timeout)
            try {
                future.get(5, java.util.concurrent.TimeUnit.SECONDS)
            } catch (e: Exception) {
                Log.e(tag, "Face detection timeout or error: ${e.message}")
                result.faces = emptyList()
                result.error = "Timeout"
            }

            val faces = result.faces ?: emptyList()

            val processingTime = System.currentTimeMillis() - startTime
            lastProcessingTime = processingTime

            Log.d(tag, "│ ✓ RESULT: ${faces.size} faces in ${processingTime}ms")
            for ((i, face) in faces.withIndex()) {
                Log.d(tag, "│   Face[$i]: (${face.x}, ${face.y}) ${face.width}x${face.height}")
            }
            Log.d(tag, "└─ PROCESS FRAME END")

            ProcessingResult(
                success = true,
                faces = faces,
                processingTime = processingTime
            )
        } catch (e: Exception) {
            Log.e("FaceProcessor", "Error processing frame: ${e.message}", e)
            ProcessingResult(
                success = false,
                faces = emptyList(),
                processingTime = System.currentTimeMillis() - startTime,
                error = e.message ?: "Unknown error"
            )
        }
    }

    fun setPixelationState(enabled: Boolean, level: Int) {
        pixelationEnabled = enabled
        pixelationLevel = level.coerceIn(1, 100)
        Log.d("FaceProcessor", "Pixelation: enabled=$enabled, level=$pixelationLevel")
    }

    fun getLastProcessingTime() = lastProcessingTime
}

data class ProcessingResult(
    val success: Boolean,
    val faces: List<RectData>,
    val processingTime: Long,
    val error: String? = null
)
