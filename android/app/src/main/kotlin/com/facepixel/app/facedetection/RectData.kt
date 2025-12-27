package com.facepixel.app.facedetection

data class RectData(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int,
    val confidence: Float = 0.5f
)
