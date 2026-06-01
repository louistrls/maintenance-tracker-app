package com.example.maintenance_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.media.Image
import android.renderscript.Allocation
import android.renderscript.Element
import android.renderscript.RenderScript
import android.renderscript.ScriptIntrinsicYuvToRGB
import android.renderscript.Type
import timber.log.Timber
import java.io.InputStream

object ImageUtils {

    // 1. LA FONCTION D'YVAN (Pour la caméra plus tard)
    fun yuvToBitmap(image: Image, context: Context): Bitmap? {
        if (image.format != ImageFormat.YUV_420_888) return null

        val rs = RenderScript.create(context)
        val yuvToRgbIntrinsic = ScriptIntrinsicYuvToRGB.create(rs, Element.U8_4(rs))

        val yuvType = Type.Builder(rs, Element.U8(rs)).setX(image.planes[0].buffer.remaining()).create()
        val inData = Allocation.createTyped(rs, yuvType, Allocation.USAGE_SCRIPT)

        val rgbaType = Type.Builder(rs, Element.RGBA_8888(rs)).setX(image.width).setY(image.height).create()
        val outData = Allocation.createTyped(rs, rgbaType, Allocation.USAGE_SCRIPT)

        inData.copyFrom(image.planes[0].buffer.array())

        yuvToRgbIntrinsic.setInput(inData)
        yuvToRgbIntrinsic.forEach(outData)

        val bitmap = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        outData.copyTo(bitmap)

        rs.destroy()
        return bitmap
    }

    // 2. NOTRE FONCTION (Pour le test statique d'aujourd'hui)
    fun getBitmapFromAsset(context: Context, filePath: String): Bitmap? {
        return try {
            val assetManager = context.assets
            val inputStream: InputStream = assetManager.open(filePath)
            BitmapFactory.decodeStream(inputStream)
        } catch (e: Exception) {
            Timber.e(e, "Erreur lors du chargement de l'image depuis les assets : \$filePath")
            null
        }
    }
}