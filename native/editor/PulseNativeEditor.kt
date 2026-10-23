package com.pulsemessenger.pulse_messenger

import android.app.Activity
import android.content.ContentValues
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

@androidx.media3.common.util.UnstableApi
class PulseNativeEditor(private val activity: Activity, messenger: BinaryMessenger) {
  private val channel=MethodChannel(messenger,"pulse/native_editor")
  private val busy=AtomicBoolean(false)
  private val cancel=AtomicBoolean(false)
  private var watermark: PulseWatermark? = null
  @Volatile private var progress=0.0
  init {
    channel.setMethodCallHandler { call,result ->
      when(call.method) {
        "progress" -> result.success(progress)
        "cancel" -> {cancel.set(true);watermark?.cancel();result.success(null)}
        "watermark" -> {
          if(!busy.compareAndSet(false,true)) {result.error("busy","An export is already running",null)}
          else {
            progress=0.0;cancel.set(false)
            val input=call.argument<String>("input") ?: ""
            val output=call.argument<String>("output") ?: ""
            val logo=call.argument<String>("logo") ?: ""
            try {
              val worker=PulseWatermark();watermark=worker
              worker.start(activity,input,output,logo,{progress=it}) {error ->
                busy.set(false);watermark=null
                if(error==null) result.success(null)
                else {File(output).delete();result.error("watermark_failed",error,null)}
              }
            } catch(e:Exception) {
              busy.set(false);watermark=null;File(output).delete()
              result.error("watermark_failed","Could not export this video with the Pulse watermark",null)
            }
          }
        }
        "avatar" -> {
          if (!busy.compareAndSet(false, true)) result.error("busy", "An export is already running", null)
          else {
            progress=0.0; cancel.set(false)
            val input=call.argument<String>("input") ?: ""
            val output=call.argument<String>("output") ?: ""
            try {
              val start=(call.argument<Number>("startMs")?.toLong() ?: -1)
              val end=(call.argument<Number>("endMs")?.toLong() ?: -1)
              require(start>=0 && end>start && end-start<=5000)
              val worker=PulseWatermark(); watermark=worker
              worker.avatar(activity,input,output,start,end,{progress=it}) {error ->
                busy.set(false); watermark=null
                if(error==null) result.success(null)
                else {File(output).delete();result.error("avatar_failed",error,null)}
              }
            } catch(e:Exception) {
              busy.set(false);watermark=null;File(output).delete()
              result.error("avatar_failed","Could not export a five-second profile video",null)
            }
          }
        }
        "style" -> {
          if (!busy.compareAndSet(false, true)) result.error("busy", "An export is already running", null)
          else {
            progress=0.0; cancel.set(false)
            val input=call.argument<String>("input") ?: ""
            val output=call.argument<String>("output") ?: ""
            try {
              val worker=PulseWatermark(); watermark=worker
              worker.style(activity,input,output,call.argument<Map<String,Any?>>("settings") ?: emptyMap(),{progress=it}) {error ->
                busy.set(false); watermark=null
                if(error==null) result.success(null)
                else {File(output).delete();result.error("style_failed",error,null)}
              }
            } catch(e:Exception) {
              busy.set(false);watermark=null;File(output).delete()
              result.error("style_failed","This device could not export these video effects. Try fewer effects or a smaller video.",null)
            }
          }
        }
        "export" -> {
          if(!busy.compareAndSet(false,true)) {result.error("busy","An export is already running",null)}
          else {
            progress=0.0;cancel.set(false)
            val input=call.argument<String>("input") ?: ""
            val output=call.argument<String>("output") ?: ""
            val start=(call.argument<Number>("startMs")?.toLong() ?: 0)*1000
            val end=(call.argument<Number>("endMs")?.toLong() ?: 0)*1000
            val mute=call.argument<Boolean>("mute") ?: false
            Thread {
              try { val actual=trim(input,output,start,end,mute);activity.runOnUiThread {result.success(mapOf("path" to output,"startMs" to actual/1000))} }
              catch(e:Exception) {File(output).delete();activity.runOnUiThread {result.error("export_failed",if(cancel.get())"Export cancelled" else "This codec cannot be exported. Try an MP4 video.",null)}}
              finally {busy.set(false)}
            }.start()
          }
        }
        "saveDownload" -> {
          val input=call.argument<String>("input") ?: ""
          val name=call.argument<String>("name") ?: "Pulse-media"
          val mime=call.argument<String>("mime") ?: "application/octet-stream"
          Thread {
            try {
              if(Build.VERSION.SDK_INT<29) throw IllegalStateException("Public downloads require Android 10 or newer")
              val values=ContentValues().apply {put(MediaStore.MediaColumns.DISPLAY_NAME,name);put(MediaStore.MediaColumns.MIME_TYPE,mime);put(MediaStore.MediaColumns.RELATIVE_PATH,Environment.DIRECTORY_DOWNLOADS+"/Pulse");put(MediaStore.MediaColumns.IS_PENDING,1)}
              val resolver=activity.contentResolver
              val uri=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values) ?: throw IllegalStateException("No download location")
              try {
                resolver.openOutputStream(uri)?.use {out->File(input).inputStream().use {it.copyTo(out,64*1024)}} ?: throw IllegalStateException("Cannot write download")
                resolver.update(uri,ContentValues().apply {put(MediaStore.MediaColumns.IS_PENDING,0)},null,null)
              } catch(e:Exception) {resolver.delete(uri,null,null);throw e}
              activity.runOnUiThread {result.success(null)}
            } catch(e:Exception) {activity.runOnUiThread {result.error("save_failed",e.message,null)}}
          }.start()
        }
        else -> result.notImplemented()
      }
    }
  }
  private fun trim(input:String,output:String,start:Long,end:Long,mute:Boolean):Long {
    require(start>=0 && end>start)
    val probe=MediaExtractor();var video=-1
    try {probe.setDataSource(input);for(i in 0 until probe.trackCount)if(probe.getTrackFormat(i).getString(MediaFormat.KEY_MIME)?.startsWith("video/")==true){video=i;break};require(video>=0);probe.selectTrack(video);probe.seekTo(start,MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
      val actual=probe.sampleTime.coerceAtLeast(0)
      val extractor=MediaExtractor();var muxer:MediaMuxer?=null;var started=false
      try {
        extractor.setDataSource(input);val writer=MediaMuxer(output,MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);muxer=writer
        val metadata=MediaMetadataRetriever()
        try {metadata.setDataSource(input);metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()?.let {writer.setOrientationHint(it)}} finally {metadata.release()}
        val tracks=HashMap<Int,Int>();var capacity=1024*1024
        for(i in 0 until extractor.trackCount){val format=extractor.getTrackFormat(i);val mime=format.getString(MediaFormat.KEY_MIME) ?: "";if(mime.startsWith("video/")||!mute&&mime.startsWith("audio/")){tracks[i]=writer.addTrack(format);extractor.selectTrack(i);if(format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))capacity=maxOf(capacity,format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))}}
        require(capacity<=16*1024*1024);writer.start();started=true;extractor.seekTo(actual,MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val buffer=ByteBuffer.allocateDirect(capacity);val info=MediaCodec.BufferInfo();var samples=0
        while(true){if(cancel.get())throw IllegalStateException("Cancelled");val time=extractor.sampleTime;val track=extractor.sampleTrackIndex;if(time<0||time>end)break
          if(time<actual){extractor.advance();continue}
          if(Build.VERSION.SDK_INT>=28)require(extractor.sampleSize<=capacity)
          buffer.clear();val size=extractor.readSampleData(buffer,0);if(size<0)break
          require((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED)==0)
          info.set(0,size,time-actual,if((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC)!=0)MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
          tracks[track]?.let {writer.writeSampleData(it,buffer,info);samples++}
          progress=((time-actual).toDouble()/(end-actual)).coerceIn(0.0,.99);extractor.advance()
        }
        require(samples>0);writer.stop();started=false;progress=1.0;return actual
      } finally {extractor.release();if(started)try{muxer?.stop()}catch(_:Exception){};muxer?.release()}
    } finally {probe.release()}
  }
}
