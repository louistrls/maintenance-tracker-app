package com.example.maintenance_app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas // Ajout pour le dessin
import androidx.compose.foundation.layout.*
import androidx.compose.material.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas // Ajout pour le texte natif
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.filament.Engine
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.TrackingFailureReason
import io.github.sceneview.ar.ARScene
import io.github.sceneview.ar.arcore.createAnchorOrNull
import io.github.sceneview.ar.arcore.getUpdatedPlanes
import io.github.sceneview.ar.arcore.isValid
import io.github.sceneview.ar.getDescription
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.ar.rememberARCameraNode
import io.github.sceneview.loaders.MaterialLoader
import io.github.sceneview.loaders.ModelLoader
import io.github.sceneview.node.CubeNode
import io.github.sceneview.node.ModelNode
import io.github.sceneview.rememberCollisionSystem
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberNodes
import io.github.sceneview.rememberOnGestureListener
import io.github.sceneview.rememberView
import kotlinx.coroutines.Dispatchers // Ajout pour l'asynchrone
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

class ArModelViewerActivity : ComponentActivity() {

    private var modelFile: String = "models/damaged_helmet.glb"

    // --- DÉBUT INTÉGRATION YOLO (Étape 1 : Déclaration) ---
    private lateinit var yoloDetector: YoloDetector
    // --- FIN INTÉGRATION YOLO ---

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        modelFile = intent.getStringExtra("model_file") ?: "models/damaged_helmet.glb"

        // --- DÉBUT INTÉGRATION YOLO (Étape 2 : Initialisation) ---
        yoloDetector = YoloDetector(this, "best_int8.tflite")
        // --- FIN INTÉGRATION YOLO ---

        setContent {
            // --- DÉBUT INTÉGRATION YOLO (Étape 3 : États Compose pour le multi-threading) ---
            val coroutineScope = rememberCoroutineScope()
            var currentDetections by remember { mutableStateOf<List<Detection>>(emptyList()) }
            var isProcessing by remember { mutableStateOf(false) }
            // --- FIN INTÉGRATION YOLO ---

            Box(
                modifier = Modifier.fillMaxSize(),
            ) {
                val engine = rememberEngine()
                val modelLoader = rememberModelLoader(engine)
                val materialLoader = rememberMaterialLoader(engine)
                val cameraNode = rememberARCameraNode(engine)
                val childNodes = rememberNodes()
                val view = rememberView(engine)
                val collisionSystem = rememberCollisionSystem(view)

                var planeRenderer by remember { mutableStateOf(true) }
                var trackingFailureReason by remember { mutableStateOf<TrackingFailureReason?>(null) }
                var frame by remember { mutableStateOf<Frame?>(null) }

                // CLEANUP nodes UNIQUEMENT ici
                DisposableEffect(Unit) {
                    onDispose {
                        childNodes.forEach {
                            try {
                                it.destroy()
                            } catch (e: Exception) {
                                Timber.tag("AR_CLEANUP").e(e, "Error destroying node: $it")
                            }
                        }
                    }
                }

                ARScene(
                    modifier = Modifier.fillMaxSize(),
                    childNodes = childNodes,
                    engine = engine,
                    view = view,
                    modelLoader = modelLoader,
                    collisionSystem = collisionSystem,
                    sessionConfiguration = { session, config ->
                        config.depthMode = if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC))
                            Config.DepthMode.AUTOMATIC else Config.DepthMode.DISABLED
                        config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
                        config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                    },
                    cameraNode = cameraNode,
                    planeRenderer = planeRenderer,
                    onTrackingFailureChanged = { trackingFailureReason = it },
                    onSessionUpdated = { session, updatedFrame ->
                        frame = updatedFrame

                        // Logique existante d'Yvan pour la pose d'ancres
                        if (childNodes.isEmpty()) {
                            updatedFrame.getUpdatedPlanes()
                                .firstOrNull { it.type == Plane.Type.HORIZONTAL_UPWARD_FACING }
                                ?.let { it.createAnchorOrNull(it.centerPose) }?.let { anchor ->
                                    childNodes += createAnchorNode(
                                        engine = engine,
                                        modelLoader = modelLoader,
                                        materialLoader = materialLoader,
                                        anchor = anchor
                                    )
                                }
                        }

                        // --- DÉBUT INTÉGRATION YOLO (Étape 4 : Interception asynchrone des images) ---
                        // On vérifie que le moteur n'est pas déjà en train de traiter une image
                        if (!isProcessing) {
                            isProcessing = true
                            try {
                                val cameraImage = updatedFrame.acquireCameraImage()

                                coroutineScope.launch(Dispatchers.Default) {
                                    try {
                                        // Conversion de l'image ARCore (YUV) en Bitmap
                                        val bitmap = ImageUtils.yuvToBitmap(cameraImage, this@ArModelViewerActivity)

                                        if (bitmap != null) {
                                            // Inférence YOLO
                                            val detections = yoloDetector.detect(bitmap)

                                            // Mise à jour de l'interface (doit toujours se faire sur le Main thread)
                                            withContext(Dispatchers.Main) {
                                                currentDetections = detections
                                            }
                                        }
                                    } catch (e: Exception) {
                                        Timber.e(e, "Erreur lors de la détection YOLO")
                                    } finally {
                                        // Libération impérative de l'image pour ne pas bloquer le flux AR
                                        cameraImage.close()
                                        isProcessing = false
                                    }
                                }
                            } catch (e: Exception) {
                                // L'image n'est pas disponible pour cette frame, on passe à la suivante
                                isProcessing = false
                            }
                        }
                        // --- FIN INTÉGRATION YOLO ---
                    },
                    onGestureListener = rememberOnGestureListener(
                        onSingleTapConfirmed = { motionEvent, node ->
                            if (node == null) {
                                val hitResults = frame?.hitTest(motionEvent.x, motionEvent.y)
                                hitResults?.firstOrNull {
                                    it.isValid(depthPoint = false, point = false)
                                }?.createAnchorOrNull()
                                    ?.let { anchor ->
                                        planeRenderer = false
                                        childNodes += createAnchorNode(
                                            engine = engine,
                                            modelLoader = modelLoader,
                                            materialLoader = materialLoader,
                                            anchor = anchor
                                        )
                                    }
                            }
                        })
                )

                // --- DÉBUT INTÉGRATION YOLO (Étape 5 : L'Overlay Canvas) ---
                // Ce Canvas est dessiné PAR-DESSUS la scène AR (grâce à l'architecture en Box d'Yvan)
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val canvasWidth = size.width
                    val canvasHeight = size.height

                    // Ratio de conversion : YOLO donne des coordonnées basées sur 640x640
                    val scaleX = canvasWidth / 640f
                    val scaleY = canvasHeight / 640f

                    currentDetections.forEach { det ->
                        val left = det.left * scaleX
                        val top = det.top * scaleY
                        val right = det.right * scaleX
                        val bottom = det.bottom * scaleY

                        // Dessin du rectangle (Bounding Box)
                        drawRect(
                            color = Color.Green,
                            topLeft = Offset(left, top),
                            size = Size(right - left, bottom - top),
                            style = Stroke(width = 8f) // Épaisseur du trait
                        )

                        // Dessin du texte (Classe + Précision)
                        drawContext.canvas.nativeCanvas.apply {
                            val paint = android.graphics.Paint().apply {
                                color = android.graphics.Color.GREEN
                                textSize = 45f
                                isFakeBoldText = true
                                setShadowLayer(4f, 2f, 2f, android.graphics.Color.BLACK) // Ombre pour la lisibilité
                            }
                            val text = "Classe ${det.classIndex} : ${(det.score * 100).toInt()}%"
                            drawText(text, left, top - 15f, paint)
                        }
                    }
                }
                // --- FIN INTÉGRATION YOLO ---

                Text(
                    modifier = Modifier
                        .systemBarsPadding()
                        .fillMaxWidth()
                        .align(Alignment.TopCenter)
                        .padding(top = 16.dp, start = 32.dp, end = 32.dp),
                    textAlign = TextAlign.Center,
                    fontSize = 28.sp,
                    color = Color.White,
                    text = trackingFailureReason?.let {
                        it.getDescription(LocalContext.current)
                    } ?: if (childNodes.isEmpty()) {
                        "Point your phone down at an empty space, and move it around slowly"
                    } else {
                        "Tap anywhere to add model"
                    }
                )
            }
        }
    }

    // --- DÉBUT INTÉGRATION YOLO (Étape 6 : Nettoyage de la RAM) ---
    override fun onDestroy() {
        super.onDestroy()
        if (::yoloDetector.isInitialized) {
            yoloDetector.close() // Ferme le moteur TensorFlow Lite pour éviter les fuites de mémoire
        }
    }
    // --- FIN INTÉGRATION YOLO ---

    private fun createAnchorNode(
        engine: Engine,
        modelLoader: ModelLoader,
        materialLoader: MaterialLoader,
        anchor: Anchor
    ): AnchorNode {
        val anchorNode = AnchorNode(engine = engine, anchor = anchor)
        val modelNode = ModelNode(
            modelInstance = modelLoader.createModelInstance(modelFile),
            scaleToUnits = 0.5f
        ).apply {
            isEditable = true
            editableScaleRange = 0.2f..0.75f
        }
        val boundingBoxNode = CubeNode(
            engine,
            size = modelNode.extents,
            center = modelNode.center,
            materialInstance = materialLoader.createColorInstance(Color.White.copy(alpha = 0.5f))
        ).apply { isVisible = false }
        modelNode.addChildNode(boundingBoxNode)
        anchorNode.addChildNode(modelNode)
        listOf(modelNode, anchorNode).forEach {
            it.onEditingChanged = { editingTransforms ->
                boundingBoxNode.isVisible = editingTransforms.isNotEmpty()
            }
        }
        return anchorNode
    }
}