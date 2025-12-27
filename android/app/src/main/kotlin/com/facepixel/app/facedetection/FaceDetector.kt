package com.facepixel.app.facedetection

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.facepixel.app.AppLogger
import java.util.concurrent.TimeUnit

class FaceDetector {
    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
            .build()
    )
    private var frameCounter = 0

    fun detectFaces(nv21Bytes: ByteArray, width: Int, height: Int, rotation: Int = 0): List<RectData> {
        return try {
            frameCounter++
            AppLogger.debug("Processing frame $frameCounter: ${width}x${height}, rotation: ${rotation}°", "detection")

            // Create InputImage from NV21 bytes directly (more efficient)
            val image = InputImage.fromByteArray(
                nv21Bytes,
                width,
                height,
                rotation, // Rotation metadata instead of physical rotation
                InputImage.IMAGE_FORMAT_NV21
            )

            // Process with ML Kit - use Tasks.await for synchronous blocking
            val task = detector.process(image)
            val faces: List<Face> = Tasks.await(task, 5000, TimeUnit.MILLISECONDS)

            AppLogger.debug("Detected ${faces.size} faces", "detection")

            val rects = faces.mapNotNull { face: Face ->
                try {
                    val bbox = face.boundingBox

                    // Estimate confidence based on face size (larger faces are typically more reliable)
                    val faceWidth = bbox.right - bbox.left
                    val faceHeight = bbox.bottom - bbox.top
                    val confidence = estimateFaceConfidence(faceWidth, faceHeight)

                    val rect = RectData(
                        x = bbox.left,
                        y = bbox.top,
                        width = faceWidth,
                        height = faceHeight,
                        confidence = confidence
                    )

                    // Only include faces that are meaningfully visible (not mostly off-screen)
                    // Skip if face is too small (less than 20x20) - prevents lingering boxes at edges
                    if (rect.width >= 20 && rect.height >= 20) {
                        rect
                    } else {
                        null
                    }
                } catch (e: Exception) {
                    AppLogger.error("Error extracting face bounds: ${e.message}", "detection", e)
                    null
                }
            }

            rects
        } catch (e: Exception) {
            AppLogger.error("Error detecting faces: ${e.message}", "detection", e)
            emptyList()
        }
    }

    fun setDetectionSensitivity(scaleFactor: Double, minNeighbors: Int) {
        // Not used with ML Kit
    }

    fun setMinFaceSize(width: Int, height: Int) {
        // Not used with ML Kit
    }

    /// Estimate face confidence based on size
    /// ML Kit doesn't expose confidence scores, so we estimate based on face dimensions
    /// Larger faces are typically more reliable (better quality detection)
    private fun estimateFaceConfidence(width: Int, height: Int): Float {
        // Base confidence for detected faces
        val minSize = 50 // pixels
        val maxSize = 400 // pixels

        val avgSize = (width + height) / 2f

        // Scale confidence from 0.5 to 1.0 based on face size
        // Small faces (20-50px): lower confidence
        // Large faces (200px+): higher confidence
        val sizeConfidence = when {
            avgSize < minSize -> 0.5f + (avgSize / minSize) * 0.3f
            avgSize > maxSize -> 0.95f
            else -> 0.5f + (avgSize / maxSize) * 0.45f
        }

        return sizeConfidence.coerceIn(0.5f, 1.0f)
    }

    fun release() {
        detector.close()
    }
}
