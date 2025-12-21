package com.facepixel.app

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.facepixel.app.facedetection.CameraFrameProcessor
import com.facepixel.app.facedetection.FaceDetector

class MainActivity : FlutterActivity() {
    private val channelName = "com.facepixel.app/faceDetection"
    private var methodChannel: MethodChannel? = null
    private var frameProcessor: CameraFrameProcessor? = null
    private var faceDetector: FaceDetector? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeFaceDetection" -> {
                    try {
                        initializeFaceDetection()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Init failed: ${e.message}", e)
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                "processFrame" -> {
                    val frameBytes = call.argument<ByteArray>("frameBytes")
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val rotation = call.argument<Int>("rotation") ?: 0
                    val isFrontCamera = call.argument<Boolean>("isFrontCamera") ?: false

                    if (frameBytes == null || width == 0 || height == 0) {
                        result.error("INVALID_ARGS", "Invalid frame parameters", null)
                        return@setMethodCallHandler
                    }

                    Log.d("MainActivity", "━━━ FRAME RECEIVED FROM FLUTTER ━━━")
                    Log.d("MainActivity", "  Size: ${width}x${height}")
                    Log.d("MainActivity", "  Rotation: ${rotation}°")
                    Log.d("MainActivity", "  Front Camera: $isFrontCamera")
                    Log.d("MainActivity", "  Bytes: ${frameBytes.size}b (expected ${(width * height * 1.5).toInt()}b)")

                    try {
                        val processingResult = frameProcessor?.processFrame(frameBytes, width, height, rotation)
                        if (processingResult != null) {
                            val facesMap = processingResult.faces.map { rect ->
                                mapOf(
                                    "x" to rect.x.toDouble(),
                                    "y" to rect.y.toDouble(),
                                    "width" to rect.width.toDouble(),
                                    "height" to rect.height.toDouble()
                                )
                            }

                            result.success(mapOf(
                                "success" to processingResult.success,
                                "faces" to facesMap,
                                "processingTime" to processingResult.processingTime
                            ))
                        } else {
                            result.error("PROCESSOR_ERROR", "Frame processor not initialized", null)
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Frame processing error: ${e.message}", e)
                        result.error("PROCESS_ERROR", e.message, null)
                    }
                }
                "setPixelationLevel" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val level = call.argument<Int>("level") ?: 50
                    frameProcessor?.setPixelationState(enabled, level)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initializeFaceDetection() {
        try {
            // Initialize components with ML Kit
            faceDetector = FaceDetector()
            frameProcessor = CameraFrameProcessor(faceDetector!!)

            Log.d("MainActivity", "Face detection initialized successfully with ML Kit")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to initialize face detection: ${e.message}", e)
            throw e
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        methodChannel?.setMethodCallHandler(null)
        faceDetector?.release()
    }
}
