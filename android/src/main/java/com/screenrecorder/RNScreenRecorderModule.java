package com.screenrecorder;
import android.widget.Toast;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.screenrecorder.RNScreenRecorder;
import java.lang.ref.WeakReference;
public class RNScreenRecorderModule extends ReactContextBaseJavaModule {
  private static WeakReference<RNScreenRecorder> mWeakActivity;
  public RNScreenRecorderModule(ReactApplicationContext reactContext) {
    super(reactContext);
  }
  public static void updateActivity(RNScreenRecorder activity) {
    mWeakActivity = new WeakReference<RNScreenRecorder>(activity);
  }
  @Override
  public String getName() {
    return "RNScreenRecorder";
  }
  @ReactMethod
  public void start() {
    mWeakActivity.get().startRecording();
    Toast.makeText(getReactApplicationContext(), "started", Toast.LENGTH_SHORT).show();
  }
  @ReactMethod
  public void stop() {
    mWeakActivity.get().stopRecording();
    String filePath = mWeakActivity.get().getVideoPath();
    getReactApplicationContext()
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
            .emit("updateFilePath", filePath);
    Toast.makeText(getReactApplicationContext(), "stopped", Toast.LENGTH_SHORT).show();
  }
}