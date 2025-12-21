package com.facepixel.app.facedetection

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.TimeUnit

class FaceDetector {
    private val tag = "FaceDetector"
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
            val expectedNV21Size = (width * height * 1.5).toInt()
            val imageDims = "${width}x${height}"
            val imageAspect = String.format("%.3f", width.toDouble() / height.toDouble())

            Log.d(tag, "╔════ FRAME $frameCounter ════╗")
            Log.d(tag, "║ Image: $imageDims (aspect=$imageAspect)")
            Log.d(tag, "║ NV21 bytes: ${nv21Bytes.size}/$expectedNV21Size")
            Log.d(tag, "║ Rotation: $rotation°")
            Log.d(tag, "╚════════════════════╝")

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

            Log.d(tag, "→ ML KIT OUTPUT: Detected ${faces.size} faces")

            val rects = faces.mapNotNull { face: Face ->
                try {
                    val bbox = face.boundingBox
                    val rect = RectData(
                        x = bbox.left,
                        y = bbox.top,
                        width = bbox.right - bbox.left,
                        height = bbox.bottom - bbox.top
                    )
                    Log.d(tag, "  Face[$face]: LEFT=${bbox.left} TOP=${bbox.top} RIGHT=${bbox.right} BOTTOM=${bbox.bottom}")
                    Log.d(tag, "  -> RectData: x=${rect.x} y=${rect.y} w=${rect.width} h=${rect.height}")
                    rect
                } catch (e: Exception) {
                    Log.e(tag, "Error extracting face bounds: ${e.message}")
                    null
                }
            }

            rects
        } catch (e: Exception) {
            Log.e(tag, "Error detecting faces: ${e.message}", e)
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
