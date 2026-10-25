package com.pulsemessenger.pulse_messenger

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Only location/roll: no recognition, identity, storage or network upload.
class PulseGiftFaces : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var detector: FaceDetector
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setMinFaceSize(0.12f).build())
        channel = MethodChannel(binding.binaryMessenger, "pulse/gift_faces")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        detector.close()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "detect") { result.notImplemented(); return }
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.size > 2000000) { result.success(null); return }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null) { result.success(null); return }
        if (bitmap.width > 1600 || bitmap.height > 1600) {
            bitmap.recycle(); result.success(null); return
        }
        detector.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { faces ->
                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }
                if (face == null) result.success(null) else {
                    val box = face.boundingBox
                    result.success(listOf(box.left.toDouble() / bitmap.width,
                        box.top.toDouble() / bitmap.height,
                        box.width().toDouble() / bitmap.width,
                        box.height().toDouble() / bitmap.height,
                        -face.headEulerAngleZ.toDouble() * Math.PI / 180))
                }
            }
            .addOnFailureListener { result.success(null) }
            .addOnCompleteListener { bitmap.recycle() }
    }
}
