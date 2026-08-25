package com.example.earplug

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "earplug/flyer_ocr",
        ).setMethodCallHandler { call, result ->
            if (call.method != "extractText") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bitmap == null) {
                result.error("invalid_image", "The flyer image could not be read.", null)
                return@setMethodCallHandler
            }

            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    result.success(
                        text.textBlocks.flatMap { block ->
                            block.lines.map { line -> line.text }
                        },
                    )
                }
                .addOnFailureListener { error ->
                    result.error("text_recognition_failed", error.localizedMessage, null)
                }
                .addOnCompleteListener {
                    bitmap.recycle()
                    recognizer.close()
                }
        }
    }
}
