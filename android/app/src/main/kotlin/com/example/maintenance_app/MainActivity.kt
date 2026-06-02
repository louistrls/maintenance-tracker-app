package com.example.maintenance_app

import android.content.Intent
import android.os.Bundle // Ajout essentiel pour utiliser onCreate
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import timber.log.Timber
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.maintenance_tracker/ar_viewer"

    // --- 1. SURCHARGE DE ONCREATE POUR LANCER LE TEST AU DÉMARRAGE ---
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialiser Timber s'il n'a pas encore été configuré
        if (Timber.treeCount == 0) {
            Timber.plant(Timber.DebugTree())
        }

        // On lance l'inférence YOLO en tâche de fond
        runYoloTest()
    }

    // --- 2. FONCTION DE TEST YOLO ---
    private fun runYoloTest() {
        val modelPath = "models/best_int8.tflite"
        val imagePath = "images/pantograph_brushes_test.jpg"

        // 1. Log de contrôle absolu pour vérifier que la fonction est bien appelée
        Log.d("YOLO_TEST", "--- LA FONCTION RUNYOLOTEST EST BIEN LANCÉE ---")

        try {
            val yoloDetector = YoloDetector(this, modelPath)
            Log.d("YOLO_TEST", "Modèle YOLO initialisé avec succès")

            val testBitmap = ImageUtils.getBitmapFromAsset(this, imagePath)

            if (testBitmap != null) {
                Log.d("YOLO_TEST", "Image chargée, début de l'inférence...")

                val startTime = System.currentTimeMillis()
                val results = yoloDetector.detect(testBitmap)
                val inferenceTime = System.currentTimeMillis() - startTime

                Log.d("YOLO_TEST", "Temps d'inférence total : $inferenceTime ms")
                Log.d("YOLO_TEST", "Nombre de détections : ${results.size}")
            } else {
                Log.e("YOLO_TEST", "Impossible de charger le Bitmap. Vérifie le nom de l'image.")
            }

            yoloDetector.close()

        } catch (e: Exception) {
            // S'il y a un crash silencieux avec TFLite, il apparaîtra ici en rouge
            Log.e("YOLO_TEST", "Erreur fatale : ${e.message}", e)
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchArViewer" -> {
                    val modelPath = call.argument<String>("modelPath")
                    Timber.tag("AR_MODEL").d("Received modelPath from Flutter: '$modelPath'")
                    launchArViewer(modelPath ?: "models/damaged_helmet.glb")
                    result.success("AR Viewer launched")
                }
                "checkArSupport" -> {
                    // Check if device supports ARCore
                    result.success(checkArCoreSupport())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun launchArViewer(modelPath: String) {
        Timber.tag("AR_MODEL").d("launchArViewer called with modelPath: '$modelPath'")
        val intent = Intent(this, ArModelViewerActivity::class.java)
        intent.putExtra("model_file", modelPath)
        startActivity(intent)
    }

    private fun checkArCoreSupport(): Boolean {
        return try {
            // Check if ARCore is supported on this device
            val availability = com.google.ar.core.ArCoreApk.getInstance().checkAvailability(this)
            availability.isSupported
        } catch (e: Exception) {
            false
        }
    }
}