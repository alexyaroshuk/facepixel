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
                    val rect = RectData(
                        x = bbox.left,
                        y = bbox.top,
                        width = bbox.right - bbox.left,
                        height = bbox.bottom - bbox.top
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

    fun release() {
        detector.close()
    }
}
