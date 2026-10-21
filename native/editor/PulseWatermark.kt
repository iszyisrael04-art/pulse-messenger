package com.pulsemessenger.pulse_messenger

import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import androidx.media3.common.Effect
import androidx.media3.effect.Brightness
import androidx.media3.effect.Contrast
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbFilter
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.TextOverlay
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

@UnstableApi
class PulseWatermark {
  private var transformer: Transformer? = null
  private var finish: ((String?) -> Unit)? = null
  private val handler = Handler(Looper.getMainLooper())
  private var tick: Runnable? = null

  fun start(activity: Activity, input: String, output: String, logo: String,
            progress: (Double) -> Unit, done: (String?) -> Unit) {
    val source = requireNotNull(BitmapFactory.decodeFile(logo))
    val overlay = object : BitmapOverlay() {
      private var bitmap = source
      override fun configure(videoSize: Size) {
        super.configure(videoSize)
        val width = (minOf(videoSize.width, videoSize.height) * .30f).toInt().coerceAtLeast(32)
        bitmap = Bitmap.createScaledBitmap(source, width,
          (width.toFloat() * source.height / source.width).toInt().coerceAtLeast(1), true)
      }
      override fun getBitmap(presentationTimeUs: Long): Bitmap = bitmap
      override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        val left = (presentationTimeUs / 5_000_000L) % 2L == 0L
        return StaticOverlaySettings.Builder()
          .setAlphaScale(.88f)
          .setBackgroundFrameAnchor(if(left) -.92f else .92f, if(left) .90f else -.90f)
          .setOverlayFrameAnchor(if(left) -1f else 1f, if(left) 1f else -1f)
          .build()
      }
    }
    launch(activity, input, output, listOf(OverlayEffect(listOf(overlay))), progress, done)
  }

  fun style(activity: Activity, input: String, output: String, settings: Map<String, Any?>,
            progress: (Double) -> Unit, done: (String?) -> Unit) {
    val effects = mutableListOf<Effect>()
    val rotation = (settings["rotation"] as? Number)?.toInt() ?: 0
    require(rotation in 0..3)
    if (rotation != 0) effects.add(ScaleAndRotateTransformation.Builder().setRotationDegrees(-90f * rotation).build())
    val ratio = (settings["ratio"] as? Number)?.toFloat()
    if (ratio != null) { require(ratio > 0f && ratio <= 4f); effects.add(Presentation.createForAspectRatio(ratio, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP)) }
    val brightness = ((settings["brightness"] as? Number)?.toFloat() ?: 0f).coerceIn(-.4f, .4f)
    val contrast = ((settings["contrast"] as? Number)?.toFloat() ?: 0f).coerceIn(-.5f, .5f)
    if (brightness != 0f) effects.add(Brightness(brightness))
    if (contrast != 0f) effects.add(Contrast(contrast))
    if (settings["mono"] == true) effects.add(RgbFilter.createGrayscaleFilter())
    val text = (settings["text"] as? String ?: "").take(80)
    if (text.isNotEmpty()) {
      val span = SpannableString(text)
      span.setSpan(ForegroundColorSpan(Color.WHITE), 0, span.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
      span.setSpan(RelativeSizeSpan(.35f), 0, span.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
      val overlay = TextOverlay.createStaticTextOverlay(span, StaticOverlaySettings.Builder()
        .setBackgroundFrameAnchor(0f, -.65f).setOverlayFrameAnchor(0f, 0f).build())
      effects.add(OverlayEffect(listOf(overlay)))
    }
    launch(activity, input, output, effects, progress, done)
  }

  private fun launch(activity: Activity, input: String, output: String, effects: List<Effect>,
                     progress: (Double) -> Unit, done: (String?) -> Unit) {
    finish = done
    val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(input))))
      .setEffects(Effects(emptyList(), effects))
      .build()
    val worker = Transformer.Builder(activity)
      .setVideoMimeType(MimeTypes.VIDEO_H264)
      .setAudioMimeType(MimeTypes.AUDIO_AAC)
      .addListener(object : Transformer.Listener {
        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
          progress(1.0); complete(null)
        }
        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
          File(output).delete(); complete("Could not export this video. Try a smaller MP4 video.")
        }
      }).build()
    transformer = worker
    worker.start(item, output)
    val polling = object : Runnable {
      override fun run() {
        val holder = ProgressHolder()
        val current = transformer ?: return
        if (current.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) progress(holder.progress / 100.0)
        handler.postDelayed(this, 200)
      }
    }
    tick = polling
    handler.post(polling)
  }

  private fun complete(error: String?) {
    tick?.let { handler.removeCallbacks(it) }; tick = null
    transformer = null
    val callback = finish; finish = null
    callback?.invoke(error)
  }

  fun cancel() {
    transformer?.cancel()
    complete("Download cancelled")
  }
}
