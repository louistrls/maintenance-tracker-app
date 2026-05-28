package com.example.maintenance_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.media.Image
import android.renderscript.Allocation
import android.renderscript.Element
import android.renderscript.RenderScript
import android.renderscript.ScriptIntrinsicYuvToRGB
import android.renderscript.Type

object ImageUtils {
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
}