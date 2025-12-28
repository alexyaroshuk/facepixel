package com.facepixel.app.facedetection

import com.facepixel.app.AppLogger
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

class CameraFrameProcessor(
    private val faceDetector: FaceDetector
) {
    private var pixelationEnabled = false
    private var pixelationLevel = 50
    private var lastProcessingTime = 0L
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    // Store latest result atomically to avoid blocking
    private val latestResultRef = AtomicReference<ProcessingResult>(
        ProcessingResult(success = true, faces = emptyList(), processingTime = 0L)
    )

    // Track if detection is currently running to skip frames
    private val isDetecting = AtomicReference(false)
    private var frameDropCount = 0
    private var frameProcessCount = 0

    fun processFrame(
        nv21Bytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int = 0
    ): ProcessingResult {
        // CRITICAL OPTIMIZATION: Skip frame if detection is still running
        // This prevents main thread from blocking and allows new frames to be processed
        if (isDetecting.getAndSet(true)) {
            frameDropCount++
            // Return immediately with cached result - don't block!
            return latestResultRef.get()
        }

        frameProcessCount++

        // Submit detection to background thread without waiting
        backgroundExecutor.submit {
            try {
                val startTime = System.currentTimeMillis()

                // Detect faces on background thread
                val faces = faceDetector.detectFaces(nv21Bytes, width, height, rotation)

                val processingTime = System.currentTimeMillis() - startTime
                lastProcessingTime = processingTime

                AppLogger.debug(
                    "Detected ${faces.size} faces in ${processingTime}ms (dropped: $frameDropCount, processed: $frameProcessCount)",
                    "processing"
                )

                // Store result atomically for next call
                latestResultRef.set(
                    ProcessingResult(
                        success = true,
                        faces = faces,
                        processingTime = processingTime
                    )
                )
            } catch (e: Exception) {
                AppLogger.error("Face detection error: ${e.message}", "processing", e)
                latestResultRef.set(
                    ProcessingResult(
                        success = false,
                        faces = emptyList(),
                        processingTime = 0L,
                        error = e.message
                    )
                )
            } finally {
                // Mark detection as complete - allows next frame to process
                isDetecting.set(false)
            }
        }

        // Return cached result immediately without blocking
        return latestResultRef.get()
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
