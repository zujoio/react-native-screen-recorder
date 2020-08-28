package com.screenrecorder;

import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.MediaRecorder;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Bundle;
import android.os.Environment;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.SparseIntArray;
import android.view.Surface;
import android.widget.Toast;
import com.facebook.react.ReactActivity;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import java.io.IOException;

public class RecorderManager extends ReactContextBaseJavaModule {

  public RecorderManager(ReactApplicationContext reactContext) {
    super(reactContext);
    this.context = (Context) reactContext;
  }

  @Override
  public String getName() {
    return "RecorderManager";
  }

  private static final int REQUEST_CODE = 1000;
  private int mScreenDensity;
  private MediaProjectionManager mProjectionManager;
  private static final int DISPLAY_WIDTH = 720;
  private static final int DISPLAY_HEIGHT = 1280;
  private MediaProjection mMediaProjection;
  private VirtualDisplay mVirtualDisplay;
  private MediaProjectionCallback mMediaProjectionCallback;
  private MediaRecorder mMediaRecorder;
  private static final SparseIntArray ORIENTATIONS = new SparseIntArray();
  private String videoPath;

  static {
    ORIENTATIONS.append(Surface.ROTATION_0, 90);
    ORIENTATIONS.append(Surface.ROTATION_90, 0);
    ORIENTATIONS.append(Surface.ROTATION_180, 270);
    ORIENTATIONS.append(Surface.ROTATION_270, 180);
  }

  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    RecorderManager.updateActivity(this);

    DisplayMetrics metrics = new DisplayMetrics();
    getWindowManager().getDefaultDisplay().getMetrics(metrics);
    mScreenDensity = metrics.densityDpi;

    mMediaRecorder = null;

    mProjectionManager =
      (MediaProjectionManager) getSystemService(
        Context.MEDIA_PROJECTION_SERVICE
      );
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != REQUEST_CODE) {
      Log.e(TAG, "Unknown request code: " + requestCode);
      return;
    }
    if (resultCode != RESULT_OK) {
      mMediaRecorder = null;
      mMediaProjection = null;
      return;
    }

    try {
      mMediaProjectionCallback = new MediaProjectionCallback();
      mMediaProjection =
        mProjectionManager.getMediaProjection(resultCode, data);
      mMediaProjection.registerCallback(mMediaProjectionCallback, null);
      mVirtualDisplay = createVirtualDisplay();
      mMediaRecorder.start();
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  @ReactMethod
  public void start() {
    try {
      initRecorder();
      shareScreen();
    } catch (Exception e) {
      e.printStackTrace();
      mMediaRecorder = null;
      mMediaProjection = null;
    }
  }

  @ReactMethod
  public void stop() {
    if (mMediaRecorder == null) {
      return;
    }
    try {
      mMediaRecorder.setOnErrorListener(null);
      mMediaRecorder.stop();
      mMediaRecorder.reset();
      stopScreenSharing();
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  public String getVideoPath() {
    return videoPath;
  }

  private void shareScreen() {
    if (mMediaProjection == null) {
      startActivityForResult(
        mProjectionManager.createScreenCaptureIntent(),
        REQUEST_CODE
      );
      return;
    }
    mVirtualDisplay = createVirtualDisplay();
    mMediaRecorder.start();
  }

  private VirtualDisplay createVirtualDisplay() {
    return mMediaProjection.createVirtualDisplay(
      "RecorderManager",
      DISPLAY_WIDTH,
      DISPLAY_HEIGHT,
      mScreenDensity,
      DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
      mMediaRecorder.getSurface(),
      null/*Callbacks*/,
      null
      /*Handler*/
    );
  }

  private void initRecorder() {
    try {
      mMediaRecorder = new MediaRecorder();
      mMediaRecorder.setVideoSource(MediaRecorder.VideoSource.SURFACE);
      mMediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP);
      videoPath =
        Environment.getExternalStoragePublicDirectory(
          Environment.DIRECTORY_DOWNLOADS
        ) +
        "/video.mp4";
      mMediaRecorder.setOutputFile(videoPath);
      mMediaRecorder.setVideoSize(DISPLAY_WIDTH, DISPLAY_HEIGHT);
      mMediaRecorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264);
      mMediaRecorder.setVideoEncodingBitRate(512 * 1000);
      mMediaRecorder.setVideoFrameRate(30);
      int rotation = getWindowManager().getDefaultDisplay().getRotation();
      int orientation = ORIENTATIONS.get(rotation + 90);
      mMediaRecorder.setOrientationHint(orientation);
      mMediaRecorder.prepare();
    } catch (IOException e) {
      e.printStackTrace();
    }
  }

  private class MediaProjectionCallback extends MediaProjection.Callback {

    @Override
    public void onStop() {
      stopRecording();
    }
  }

  private void stopScreenSharing() {
    if (mVirtualDisplay == null) {
      return;
    }
    mVirtualDisplay.release();
    mVirtualDisplay = null;
    mMediaRecorder.release();
    mMediaRecorder = null;
    destroyMediaProjection();
  }

  @Override
  public void onDestroy() {
    super.onDestroy();
    destroyMediaProjection();
  }

  private void destroyMediaProjection() {
    if (mMediaProjection != null) {
      mMediaProjection.unregisterCallback(mMediaProjectionCallback);
      mMediaProjection.stop();
      mMediaProjection = null;
    }
    Log.i(TAG, "MediaProjection Stopped");
  }
}
