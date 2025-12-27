package com.facepixel.app.facedetection

import com.facepixel.app.AppLogger
import java.util.concurrent.Executors

class CameraFrameProcessor(
    private val faceDetector: FaceDetector
) {
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

        return try {
            // Pass NV21 bytes directly to ML Kit (more efficient than bitmap conversion)
            val result = object : Any() {
                var faces: List<RectData>? = null
                var error: String? = null
            }

            // Execute on background thread and wait
            val future = backgroundExecutor.submit {
                try {
                    result.faces = faceDetector.detectFaces(nv21Bytes, width, height, rotation)
                } catch (e: Exception) {
                    result.error = e.message
                    AppLogger.error("Face detection error: ${e.message}", "processing", e)
                }
            }

            // Wait for completion (with timeout)
            try {
                future.get(5, java.util.concurrent.TimeUnit.SECONDS)
            } catch (e: Exception) {
                AppLogger.warn("Face detection timeout: ${e.message}", "processing")
                result.faces = emptyList()
                result.error = "Timeout"
            }

            val faces = result.faces ?: emptyList()

            val processingTime = System.currentTimeMillis() - startTime
            lastProcessingTime = processingTime

            AppLogger.debug("Processing completed: ${faces.size} faces in ${processingTime}ms", "processing")

            ProcessingResult(
                success = true,
                faces = faces,
                processingTime = processingTime
            )
        } catch (e: Exception) {
            AppLogger.error("Error processing frame: ${e.message}", "processing", e)
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
        AppLogger.debug("Pixelation: enabled=$enabled, level=$pixelationLevel", "processing")
    }

    fun getLastProcessingTime() = lastProcessingTime
}

data class ProcessingResult(
    val success: Boolean,
    val faces: List<RectData>,
    val processingTime: Long,
    val error: String? = null
)
