package com.wmmt.port;

import android.app.Activity;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.hardware.display.DisplayManager;
import android.media.MediaPlayer;
import android.hardware.input.InputManager;
import android.os.Bundle;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.Display;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.VideoView;

import java.io.File;

/* The Android side of the port, as main.m is the iOS one: the game draws on a SurfaceView
 * from its own thread (src/main_android.c), the attract movies play in a VideoView over it,
 * the BGM in a MediaPlayer (both decode the AAC/H.264 in hardware); touches, the gravity for
 * steering by tilt and the lifecycle go down to the native side. */
public class MainActivity extends Activity implements SurfaceHolder.Callback, SensorEventListener, DisplayManager.DisplayListener, InputManager.InputDeviceListener {
  static { System.loadLibrary("wmmt"); }

  static native void nativeStart(MainActivity a, String dataDir, String saveDir);
  static native void nativeSurface(Surface s, int w, int h);
  static native void nativeTouch(int id, int phase, float x, float y);
  static native void nativePad(int on, int buttons, float lx, float ly, float rx, float ry, float lt, float rt);
  static native void nativePause(boolean p);
  static native void nativeTilt(float radians);
  static native boolean nativeWantsTilt();
  static native void nativeMovieDone();
  static native void nativeRefresh(float hz);
  static native void nativePressStart();
  static native void nativeMemoryWarning();

  private FrameLayout root;
  private SurfaceView game;
  private VideoView movie;
  private MediaPlayer bgm;
  private float bgmVolume = 1.0f; /* app_bgm_level's: a new track takes it too */
  private String dataDir;
  private SensorManager sensors;
  private Sensor gravity;
  /* the controller: app.h's PAD_* held on its keys and on its hat, its axes */
  private InputManager inputs;
  private boolean padOn;
  private android.os.Vibrator padMotors; /* the connected pad's motors, null none */
  private int padKeys, padHat;
  private float padLx, padLy, padRx, padRy, padLt, padRt;

  @Override protected void onCreate(Bundle b) {
    super.onCreate(b);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON | WindowManager.LayoutParams.FLAG_FULLSCREEN);
    if (android.os.Build.VERSION.SDK_INT >= 28)
      getWindow().getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
    root = new FrameLayout(this);
    game = new SurfaceView(this);
    game.getHolder().addCallback(this);
    game.setOnTouchListener((v, e) -> { touch(e); return true; });
    root.addView(game);
    setContentView(root);
    hideBars();
    /* the data as adb pushes it: /sdcard/Android/data/com.wmmt.port/files/wmmt (needs no
     * storage permission); the player's files next to it */
    File ext = getExternalFilesDir(null);
    File data = new File(ext, "wmmt");
    data.mkdirs();
    dataDir = data.getAbsolutePath();
    sensors = (SensorManager) getSystemService(SENSOR_SERVICE);
    gravity = sensors.getDefaultSensor(Sensor.TYPE_GRAVITY);
    /* test settings, as a desktop run has them in its environment:
     * am start -n com.wmmt.port/.MainActivity --es env "WMMT_HQ_LEVEL=3;WMMT_PILOT=1"
     * (only WMMT_ names: the activity is open to any app on the phone) */
    String env = getIntent().getStringExtra("env");
    if (env != null) for (String kv : env.split(";")) {
      int eq = kv.indexOf('=');
      if (eq > 0 && kv.startsWith("WMMT_")) {
        try { android.system.Os.setenv(kv.substring(0, eq), kv.substring(eq + 1), true); }
        catch (android.system.ErrnoException e) { /* the run just goes on without it */ }
      }
    }
    nativeStart(this, dataDir, dataDir);
    ((DisplayManager) getSystemService(DISPLAY_SERVICE)).registerDisplayListener(this, null);
    inputs = (InputManager) getSystemService(INPUT_SERVICE);
    inputs.registerInputDeviceListener(this, null);
    padScan();
  }

  private void hideBars() {
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
  }

  @Override public void onWindowFocusChanged(boolean f) {
    super.onWindowFocusChanged(f);
    if (f) hideBars();
  }

  private void touch(MotionEvent e) {
    int a = e.getActionMasked();
    if (a == MotionEvent.ACTION_MOVE) {
      for (int i = 0; i < e.getPointerCount(); ++i) nativeTouch(e.getPointerId(i), 1, e.getX(i), e.getY(i));
      return;
    }
    int phase = a == MotionEvent.ACTION_DOWN || a == MotionEvent.ACTION_POINTER_DOWN ? 0
        : a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_POINTER_UP ? 2 : a == MotionEvent.ACTION_CANCEL ? 3 : -1;
    if (phase < 0) return;
    if (phase == 3) {
      for (int i = 0; i < e.getPointerCount(); ++i) nativeTouch(e.getPointerId(i), 2, e.getX(i), e.getY(i));
      return;
    }
    int i = e.getActionIndex();
    nativeTouch(e.getPointerId(i), phase, e.getX(i), e.getY(i));
  }

  /* ---- the controller ---- */

  /* a real one only: a false yes takes the touch keys away, and some keyboards and docks claim
   * the gamepad source without a stick or an A button */
  private static boolean isPad(InputDevice d) {
    if (d == null || d.isVirtual()) return false;
    int src = d.getSources();
    if ((src & InputDevice.SOURCE_GAMEPAD) != InputDevice.SOURCE_GAMEPAD
        && (src & InputDevice.SOURCE_JOYSTICK) != InputDevice.SOURCE_JOYSTICK) return false;
    return d.hasKeys(KeyEvent.KEYCODE_BUTTON_A)[0]
        || (d.getMotionRange(MotionEvent.AXIS_X) != null && d.getMotionRange(MotionEvent.AXIS_Y) != null);
  }

  private void padSend() { nativePad(!padOn ? 0 : padMotors != null ? 2 : 1, padKeys | padHat, padLx, padLy, padRx, padRy, padLt, padRt); }

  /* let go of everything (its key-ups never come after a disconnect or in the background) */
  private void padClear() {
    padKeys = padHat = 0;
    padLx = padLy = padRx = padRy = padLt = padRt = 0;
    padSend();
  }

  private void padScan() {
    padOn = false;
    padMotors = null;
    for (int id : inputs.getInputDeviceIds()) {
      InputDevice d = inputs.getInputDevice(id);
      if (!isPad(d)) continue;
      padOn = true;
      if (padMotors == null && d.getVibrator().hasVibrator()) padMotors = d.getVibrator();
    }
    padClear();
  }

  @Override public void onInputDeviceAdded(int id) { padScan(); }
  @Override public void onInputDeviceRemoved(int id) { padScan(); }
  @Override public void onInputDeviceChanged(int id) { padScan(); }

  /* app.h's PAD_* for a key, 0 none */
  private static int padBit(int code) {
    switch (code) {
    case KeyEvent.KEYCODE_BUTTON_A: case KeyEvent.KEYCODE_DPAD_CENTER: return 1;
    case KeyEvent.KEYCODE_BUTTON_B: case KeyEvent.KEYCODE_BACK: return 2;
    case KeyEvent.KEYCODE_BUTTON_X: return 4;
    case KeyEvent.KEYCODE_BUTTON_Y: return 8;
    case KeyEvent.KEYCODE_BUTTON_L1: return 16;
    case KeyEvent.KEYCODE_BUTTON_R1: return 32;
    case KeyEvent.KEYCODE_BUTTON_L2: return 64;
    case KeyEvent.KEYCODE_BUTTON_R2: return 128;
    case KeyEvent.KEYCODE_BUTTON_START: return 256;
    case KeyEvent.KEYCODE_BUTTON_SELECT: return 512;
    case KeyEvent.KEYCODE_DPAD_LEFT: return 1024;
    case KeyEvent.KEYCODE_DPAD_RIGHT: return 2048;
    default: return 0;
    }
  }

  @Override public boolean dispatchKeyEvent(KeyEvent e) {
    int bit = padBit(e.getKeyCode());
    if (bit == 0 || !isPad(e.getDevice())) return super.dispatchKeyEvent(e);
    if (e.getAction() == KeyEvent.ACTION_DOWN) padKeys |= bit;
    else if (e.getAction() == KeyEvent.ACTION_UP) padKeys &= ~bit;
    padSend();
    return true;
  }

  @Override public boolean dispatchGenericMotionEvent(MotionEvent e) {
    if ((e.getSource() & InputDevice.SOURCE_JOYSTICK) != InputDevice.SOURCE_JOYSTICK
        || e.getAction() != MotionEvent.ACTION_MOVE || !isPad(e.getDevice())) return super.dispatchGenericMotionEvent(e);
    padLx = e.getAxisValue(MotionEvent.AXIS_X);
    padLy = e.getAxisValue(MotionEvent.AXIS_Y);
    padRx = e.getAxisValue(MotionEvent.AXIS_Z);
    padRy = e.getAxisValue(MotionEvent.AXIS_RZ);
    /* the triggers: Xbox and PlayStation pads report the first of each pair, others the second */
    padLt = Math.max(e.getAxisValue(MotionEvent.AXIS_LTRIGGER), e.getAxisValue(MotionEvent.AXIS_BRAKE));
    padRt = Math.max(e.getAxisValue(MotionEvent.AXIS_RTRIGGER), e.getAxisValue(MotionEvent.AXIS_GAS));
    float hat = e.getAxisValue(MotionEvent.AXIS_HAT_X);
    padHat = hat < -0.5f ? 1024 : hat > 0.5f ? 2048 : 0;
    padSend();
    return true;
  }

  @Override public void surfaceCreated(SurfaceHolder h) {}
  /* the OPTION screen's FPS (the game's thread tells it, app_fps) */
  private int wantFps = 120;

  /* the slowest refresh the display has at this size that reaches wantFps, else its fastest (above
   * 60 the race draws between the arcade's 60 Hz frames), and the native side told what it really
   * runs at: battery saver and the system's motion smoothness setting can hold it at 60 */
  private void askRate() {
    Surface s = game.getHolder().getSurface();
    Display d = getWindowManager().getDefaultDisplay();
    Display.Mode now = d.getMode(), best = now;
    float want = wantFps - 1; /* (a 59.94 Hz mode is a 60) */
    for (Display.Mode m : d.getSupportedModes())
      if (m.getPhysicalWidth() == now.getPhysicalWidth() && m.getPhysicalHeight() == now.getPhysicalHeight()
          && (best.getRefreshRate() < want ? m.getRefreshRate() > best.getRefreshRate()
                                           : m.getRefreshRate() >= want && m.getRefreshRate() < best.getRefreshRate())) best = m;
    WindowManager.LayoutParams a = getWindow().getAttributes();
    if (a.preferredDisplayModeId != best.getModeId()) {
      a.preferredDisplayModeId = best.getModeId();
      getWindow().setAttributes(a);
    }
    if (s.isValid() && android.os.Build.VERSION.SDK_INT >= 30)
      s.setFrameRate(best.getRefreshRate(), Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE);
    nativeRefresh(d.getRefreshRate());
  }

  @Override public void onDisplayAdded(int id) {}
  @Override public void onDisplayRemoved(int id) {}
  @Override public void onDisplayChanged(int id) { nativeRefresh(getWindowManager().getDefaultDisplay().getRefreshRate()); }

  @Override public void surfaceChanged(SurfaceHolder h, int fmt, int w, int ht) {
    askRate();
    nativeSurface(h.getSurface(), w, ht);
  }
  @Override public void surfaceDestroyed(SurfaceHolder h) { nativeSurface(null, 0, 0); }

  @Override protected void onPause() {
    super.onPause();
    nativePause(true);
    padClear();
    sensors.unregisterListener(this);
    if (bgm != null) bgm.pause();
    if (movie != null) movie.pause();
  }

  @Override protected void onResume() {
    super.onResume();
    hideBars();
    nativePause(false);
    padScan(); /* (one connected or gone while away) */
    if (gravity != null) sensors.registerListener(this, gravity, SensorManager.SENSOR_DELAY_GAME);
    if (bgm != null) bgm.start();
    if (movie != null) movie.start();
  }

  @Override public void onTrimMemory(int level) {
    super.onTrimMemory(level);
    if (level >= TRIM_MEMORY_RUNNING_LOW) nativeMemoryWarning();
  }

  /* the phone turned like a wheel (main.m's tilt): gravity's angle in the screen's plane from
   * its down, clockwise positive; nothing when it lies flat. In landscape the screen's right is
   * the sensor's -y (rotation 90) or +y (270) and its down the sensor's +x or -x. */
  @Override public void onSensorChanged(SensorEvent e) {
    if (!nativeWantsTilt()) return;
    float gx = e.values[0], gy = e.values[1];
    int rot = getWindowManager().getDefaultDisplay().getRotation();
    float right = rot == Surface.ROTATION_270 ? gy : -gy, down = rot == Surface.ROTATION_270 ? -gx : gx;
    float g2 = right * right + down * down;
    nativeTilt(g2 < 0.04f * 96.2f ? 0.0f : (float) Math.atan2(-right, down));
  }
  @Override public void onAccuracyChanged(Sensor s, int a) {}

  /* ---- called by the game's thread ---- */

  /* a pulse of the controller's motors (amp 1..255); off this thread, a call that can wait on
   * the system would cost the race its frame */
  void padRumble(final int ms, final int amp) {
    runOnUiThread(() -> {
      if (padMotors != null) padMotors.vibrate(android.os.VibrationEffect.createOneShot(ms, amp));
    });
  }

  void setFps(final int fps) {
    runOnUiThread(() -> {
      wantFps = fps;
      askRate();
    });
  }

  /* the attract movie (data dir's intro.mp4 etc.), or none for null */
  void showMovie(final String name) {
    runOnUiThread(() -> {
      if (movie != null) {
        movie.stopPlayback();
        root.removeView(movie);
        movie = null;
      }
      if (name == null) return;
      File f = new File(dataDir, name);
      if (!f.exists()) {
        nativeMovieDone();
        return;
      }
      movie = new VideoView(this);
      movie.setZOrderMediaOverlay(true);
      movie.setVideoPath(f.getAbsolutePath());
      movie.setOnCompletionListener(mp -> nativeMovieDone());
      movie.setOnErrorListener((mp, what, extra) -> { nativeMovieDone(); return true; });
      /* a tap on the movie is the arcade's "press the gas" */
      movie.setOnTouchListener((v, e) -> {
        if (e.getActionMasked() == MotionEvent.ACTION_DOWN) nativePressStart();
        return true;
      });
      FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
          FrameLayout.LayoutParams.MATCH_PARENT, android.view.Gravity.CENTER);
      /* the intro's picture is letterboxed in its 4:3 (640x326 at y 76): on a wider screen it
       * goes the screen's width, its black bands off the top and bottom; playdemo and tutorial
       * fill their 4:3 and stay so */
      int w = root.getWidth(), h = root.getHeight();
      if (name.equals("intro.mp4") && w * 3 > h * 4) {
        lp.width = w;
        lp.height = w * 3 / 4;
      }
      root.addView(movie, lp);
      movie.start();
    });
  }

  /* data dir's sound/bgm/<name>.m4a over and over, or nothing for null */
  void playBgm(final String name) {
    runOnUiThread(() -> {
      if (bgm != null) {
        bgm.release();
        bgm = null;
      }
      if (name == null) return;
      File f = new File(dataDir, "sound/bgm/" + name + ".m4a");
      if (!f.exists()) return;
      try {
        bgm = new MediaPlayer();
        bgm.setDataSource(f.getAbsolutePath());
        bgm.setLooping(true);
        bgm.setVolume(bgmVolume, bgmVolume);
        bgm.prepare();
        bgm.start();
      } catch (Exception ex) {
        bgm = null;
      }
    });
  }

  /* the BGM's level (the card's BGM volume, the story ending's fade out) */
  void bgmLevel(final float level) {
    runOnUiThread(() -> {
      bgmVolume = level;
      if (bgm != null) bgm.setVolume(level, level);
    });
  }

  void fail(final String msg) {
    runOnUiThread(() -> new android.app.AlertDialog.Builder(this).setTitle("WMMT3DX").setMessage(msg)
        .setPositiveButton("OK", null).show());
  }
}
