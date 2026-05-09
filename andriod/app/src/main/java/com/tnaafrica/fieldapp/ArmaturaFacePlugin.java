package com.tnaafrica.fieldapp;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.provider.Settings;
import android.util.Base64;
import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import com.armatura.facepro.AMTFaceProService;
import com.armatura.facepro.ver56.auth.FaceAuthNative;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import org.json.JSONObject;

// ⚡ NEW CAMERA IMPORTS ⚡
import android.hardware.Camera;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.FrameLayout;

@CapacitorPlugin(name = "ArmaturaFace")
public class ArmaturaFacePlugin extends Plugin {

    private boolean isEngineInitialized = false;

    // ⚡ NATIVE CAMERA VARIABLES ⚡
    private Camera mCamera;
    private FrameLayout cameraContainer;
    private boolean isScanning = false;
    private byte[] rotatedNV21; // ⚡ Buffer for upright frames

    @PluginMethod
    public void initEngine(PluginCall call) {
        // Ask the new Brain if it's already awake
        if (isEngineInitialized && FaceRepository.getInstance().isInit()) {
            call.resolve();
            return;
        }

        final Context appContext = getContext().getApplicationContext();

        // ⚡ 1. STORAGE PERMISSIONS ⚡
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            if (!android.os.Environment.isExternalStorageManager()) {
                android.content.Intent intent = new android.content.Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                intent.setData(android.net.Uri.parse("package:" + appContext.getPackageName()));
                getActivity().startActivity(intent);
                call.reject("CRITICAL: Armatura SDK requires 'All Files Access'. Grant permission and try again.");
                return;
            }
        }

        try {
            Log.d("ArmaturaFace", "Initiating Boot Sequence...");

            // ⚡ 2. THE OFFLINE SHIELD (PAGE 15 OF MANUAL) ⚡
            if (AMTFaceProService.isAuthorized()) {
                Log.d("ArmaturaFace", "Device is ALREADY AUTHORIZED. Bypassing network check.");

                // Set working directory before offline boot
                String licDir = appContext.getFilesDir().getAbsolutePath() + "/armatura_secure_v2/";
                byte[] dirBytes = licDir.getBytes("utf-8");
                AMTFaceProService.setParameter(0, 1011, dirBytes, dirBytes.length);
                copyModelsIfMissing(appContext);

                // ⚡ BOOT THE NEW BRAIN INSTEAD OF THE OLD CONTEXT ⚡
                boolean brainBooted = FaceRepository.getInstance().init(appContext);

                if (brainBooted) {
                    isEngineInitialized = true;
                    Log.d("ArmaturaFace", "NEW BRAIN BOOTED SAFELY FROM INTERNAL CACHE!");
                    call.resolve();
                    return;
                } else {
                    Log.e("ArmaturaFace", "Authorized but Brain init failed.");
                    call.reject("Brain init failed");
                    return;
                }
            }

            Log.d("ArmaturaFace", "Not authorized locally. Fetching from network...");
            final String token = "0D2B2AE7F75C4215A304F29785D32A99";
            final String[] fpResult = new String[]{null};
            final int[] initResult = new int[]{-1};
            final java.util.concurrent.CountDownLatch latch = new java.util.concurrent.CountDownLatch(1);

            // ⚡ 3. GET FINGERPRINT ⚡
            getActivity().runOnUiThread(() -> {
                try {
                    initResult[0] = FaceAuthNative.init(appContext);
                    fpResult[0] = FaceAuthNative.getDeviceFingerprint();
                } catch (Exception e) {
                    Log.e("ArmaturaFace", "Native Fingerprint Error", e);
                } finally {
                    latch.countDown();
                }
            });
            latch.await();

            if (fpResult[0] == null || fpResult[0].isEmpty()) {
                call.reject("Hardware Fingerprint Generation Failed. Code: " + initResult[0]);
                return;
            }

            // ⚡ 4. PARSE FINGERPRINT ⚡
            JSONObject fpJson = new JSONObject(fpResult[0]);
            String fingerPrint = fpJson.getString("context");
            String faceSDKData = fpJson.getString("facesdkdata");
            long faceSDKDataCheck = fpJson.getLong("facesdkdatacheck");
            String faceSDKRID = fpJson.getString("facesdkrid");
            long faceSDKRIDCheck = fpJson.getLong("facesdkridcheck");

            String sn = FaceAuthNative.getHardwareID();
            if (sn == null || sn.isEmpty()) {
                Log.w("ArmaturaFace", "C++ Hardware ID failed. Falling back to native Android ID.");
                sn = Settings.Secure.getString(appContext.getContentResolver(), Settings.Secure.ANDROID_ID);
            }

            if (sn == null || sn.isEmpty()) {
                call.reject("Cannot fetch C++ Hardware ID or Native Android ID.");
                return;
            }
            Log.d("ArmaturaFace", "Requesting Permanent License for Hardware ID: " + sn);

            // ⚡ 5. FETCH FROM LMS ⚡
            String serverUrl = "https://license.armatura.us/api/alms/getLicense?access_token=" + token + "&apikey=" + token + "&api_key=" + token;
            URL url = new URL(serverUrl);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json; utf-8");
            conn.setRequestProperty("Accept", "application/json");
            conn.setRequestProperty("Authorization", "Bearer " + token);
            conn.setDoOutput(true);

            JSONObject payload = new JSONObject();
            // Force Android ID for the payload, exactly like FaceProUtil
            String androidIdForPayload = Settings.Secure.getString(appContext.getContentResolver(), Settings.Secure.ANDROID_ID);
            payload.put("sn", androidIdForPayload);
            payload.put("licenseType", "1");
            payload.put("deviceFp", fingerPrint);
            payload.put("facesdkdata", faceSDKData);
            payload.put("facesdkdatacheck", faceSDKDataCheck);
            payload.put("facesdkrid", faceSDKRID);
            payload.put("facesdkridcheck", faceSDKRIDCheck);

            try (OutputStream os = conn.getOutputStream()) {
                byte[] input = payload.toString().getBytes("utf-8");
                os.write(input, 0, input.length);
            }

            int code = conn.getResponseCode();
            java.io.InputStream stream = code >= 200 && code < 300 ? conn.getInputStream() : conn.getErrorStream();
            if (stream == null) {
                call.reject("Armatura Server HTTP " + code + ": No response body stream.");
                return;
            }

            BufferedReader br = new BufferedReader(new InputStreamReader(stream, "utf-8"));
            StringBuilder response = new StringBuilder();
            String responseLine;
            while ((responseLine = br.readLine()) != null) response.append(responseLine.trim());

            JSONObject jsonResponse = new JSONObject(response.toString());

            // ⚡ 6. APPLY LICENSE & BOOT ⚡
            if (jsonResponse.has("code") && jsonResponse.getInt("code") == 0 && jsonResponse.has("data")) {

                // Fix: Extract data as a raw String, not a nested JSON Object
                String licenseStringPayload = jsonResponse.getString("data");
                int authRet = FaceAuthNative.setLicense(licenseStringPayload);
                Log.d("ArmaturaFace", "Native Auth Result: " + authRet);

                if (authRet == 0) {
                    // ⚡ NEW: 1. Set the working directory (1011) so the engine can find the AI models
                    String licDir = appContext.getFilesDir().getAbsolutePath() + "/armatura_secure_v2/";
                    byte[] dirBytes = licDir.getBytes("utf-8");
                    AMTFaceProService.setParameter(0, 1011, dirBytes, dirBytes.length);

                    // ⚡ NEW: 2. Copy the brain files from the APK to the working directory
                    copyModelsIfMissing(appContext);

                    // ⚡ BOOT THE NEW BRAIN INSTEAD OF THE OLD CONTEXT ⚡
                    boolean brainBooted = FaceRepository.getInstance().init(appContext);

                    if (brainBooted) {
                        isEngineInitialized = true;
                        Log.d("ArmaturaFace", "NEW BRAIN BOOTED SAFELY VIA NATIVE AUTH!");
                        call.resolve();
                    } else {
                        call.reject("Engine Boot Failed.");
                    }
                } else {
                    call.reject("FaceAuthNative rejected license. Code: " + authRet);
                }
            } else {
                call.reject("Armatura Server Denied Key: " + jsonResponse.optString("message", "Unknown Error"));
            }

        } catch (Exception e) {
            Log.e("ArmaturaFace", "FATAL CRASH in initEngine", e);
            call.reject("Engine Boot Error: " + (e.getMessage() != null ? e.getMessage() : "Exception occurred"));
        }
    }

    @PluginMethod
    public void loadTemplateIntoEngine(PluginCall call) {
        // Ask the new Brain if it's ready to accept templates
        if (!isEngineInitialized || !FaceRepository.getInstance().isInit()) {
            call.reject("Engine not initialized.");
            return;
        }

        String pin = call.getString("pin");
        String templateBase64 = call.getString("template");

        if (pin == null || templateBase64 == null) {
            call.reject("Must provide both 'pin' and 'template'.");
            return;
        }

        try {
            byte[] templateBytes = Base64.decode(templateBase64, Base64.DEFAULT);

            // Feed it directly into the new Brain's RAM
            boolean success = FaceRepository.getInstance().dbAdd(pin, templateBytes);

            if (success) {
                JSObject ret = new JSObject();
                ret.put("success", true);
                ret.put("message", "Template for " + pin + " loaded into RAM.");
                call.resolve(ret);
            } else {
                call.reject("Failed to load template into engine.");
            }
        } catch (Exception e) {
            Log.e("ArmaturaFace", "Error loading template", e);
            call.reject("Exception loading template: " + e.getMessage());
        }
    }

    @PluginMethod
    public void startCamera(PluginCall call) {
        if (!FaceRepository.getInstance().isInit()) {
            call.reject("Engine not initialized. Boot first.");
            return;
        }

        // Grab the camera direction chosen by the user in JavaScript
        String facingMode = call.getString("facingMode", "user");

        getActivity().runOnUiThread(() -> {
            try {
                // ⚡ FORCE ANDROID TO RENDER WEBVIEW AS TRANSPARENT ⚡
                if (getBridge() != null && getBridge().getWebView() != null) {
                    getBridge().getWebView().setBackgroundColor(android.graphics.Color.TRANSPARENT);
                }
                getActivity().getWindow().getDecorView().setBackgroundColor(android.graphics.Color.TRANSPARENT);

                // 1. Build the Native Camera Container (The "Glass Floor")
                if (cameraContainer == null) {
                    cameraContainer = new FrameLayout(getContext());
                    FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                    );
                    cameraContainer.setLayoutParams(params);

                    // Inject it at the very bottom layer (index 0) of the Android Window
                    ViewGroup rootView = (ViewGroup) getActivity().getWindow().getDecorView().getRootView();
                    rootView.addView(cameraContainer, 0);
                }

                // 2. Open the Selected Camera
                int cameraId = -1;
                int targetFacing = facingMode.equals("environment") ? Camera.CameraInfo.CAMERA_FACING_BACK : Camera.CameraInfo.CAMERA_FACING_FRONT;

                Camera.CameraInfo info = new Camera.CameraInfo();
                for (int i = 0; i < Camera.getNumberOfCameras(); i++) {
                    Camera.getCameraInfo(i, info);
                    if (info.facing == targetFacing) {
                        cameraId = i;
                        break;
                    }
                }
                if (cameraId == -1) cameraId = 0; // Fallback

                mCamera = Camera.open(cameraId);

                // Force Portrait Orientation
                mCamera.setDisplayOrientation(90);

                // ⚡ FIX 1: HIGH-RES & AUTO-FOCUS (Stops Blurriness) ⚡
                Camera.Parameters parameters = mCamera.getParameters();
                java.util.List<Camera.Size> supportedSizes = parameters.getSupportedPreviewSizes();
                Camera.Size bestSize = supportedSizes.get(0);
                long maxArea = 0;
                for (Camera.Size size : supportedSizes) {
                    long area = size.width * size.height;
                    // Cap at 1080p (1920 width) to prevent the Java byte-rotation loop from lagging the CPU
                    if (area > maxArea && size.width <= 1920) {
                        maxArea = area;
                        bestSize = size;
                    }
                }
                parameters.setPreviewSize(bestSize.width, bestSize.height);

                // Enable Continuous Auto-Focus if supported by the lens
                java.util.List<String> focusModes = parameters.getSupportedFocusModes();
                if (focusModes != null) {
                    if (focusModes.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE)) {
                        parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
                    } else if (focusModes.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO)) {
                        parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
                    }
                }
                mCamera.setParameters(parameters);

                // 3. Create the Surface to draw the video onto
                SurfaceView surfaceView = new SurfaceView(getContext());

                // ⚡ FIX 2: ASPECT RATIO CENTER CROP (Stops Elongation) ⚡
                int screenWidth = getActivity().getWindow().getDecorView().getWidth();
                int screenHeight = getActivity().getWindow().getDecorView().getHeight();

                // Because the camera is rotated 90 degrees, we swap preview width and height for the math
                int camWidth = bestSize.height;
                int camHeight = bestSize.width;

                float screenRatio = (float) screenHeight / screenWidth;
                float camRatio = (float) camHeight / camWidth;

                int finalWidth, finalHeight;
                if (screenRatio > camRatio) {
                    // Screen is taller. Match height, scale width proportionally.
                    finalHeight = screenHeight;
                    finalWidth = (int) (screenHeight / camRatio);
                } else {
                    // Screen is wider. Match width, scale height proportionally.
                    finalWidth = screenWidth;
                    finalHeight = (int) (screenWidth * camRatio);
                }

                FrameLayout.LayoutParams svParams = new FrameLayout.LayoutParams(finalWidth, finalHeight);
                svParams.gravity = android.view.Gravity.CENTER;
                surfaceView.setLayoutParams(svParams);

                cameraContainer.addView(surfaceView);

                surfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
                    @Override
                    public void surfaceCreated(SurfaceHolder holder) {
                        try {
                            mCamera.setPreviewDisplay(holder);
                            mCamera.startPreview();
                            isScanning = true;

                            // ⚡ 4. THE HIGH-SPEED NV21 FEED ⚡
                            final boolean isFront = (targetFacing == Camera.CameraInfo.CAMERA_FACING_FRONT);

                            mCamera.setPreviewCallback(new Camera.PreviewCallback() {
                                @Override
                                public void onPreviewFrame(byte[] data, Camera camera) {
                                    if (!isScanning) return;

                                    Camera.Size size = camera.getParameters().getPreviewSize();
                                    int width = size.width;
                                    int height = size.height;

                                    // 1. Allocate the rotation buffer ONCE to save RAM
                                    if (rotatedNV21 == null || rotatedNV21.length != data.length) {
                                        rotatedNV21 = new byte[data.length];
                                    }

                                    // 2. High-Speed Java Rotation (Fixes the Sideways Sensor Trap)
                                    int frameSize = width * height;
                                    int k = 0;

                                    if (isFront) {
                                        // Rotate 270 CW (Front Camera Portrait)
                                        for (int i = width - 1; i >= 0; i--) {
                                            for (int j = 0; j < height; j++) {
                                                rotatedNV21[k++] = data[j * width + i];
                                            }
                                        }
                                        k = frameSize;
                                        for (int i = width - 2; i >= 0; i -= 2) {
                                            for (int j = 0; j < height / 2; j++) {
                                                rotatedNV21[k++] = data[frameSize + j * width + i];
                                                rotatedNV21[k++] = data[frameSize + j * width + i + 1];
                                            }
                                        }
                                    } else {
                                        // Rotate 90 CW (Rear Camera Portrait)
                                        for (int i = 0; i < width; i++) {
                                            for (int j = height - 1; j >= 0; j--) {
                                                rotatedNV21[k++] = data[j * width + i];
                                            }
                                        }
                                        k = frameSize;
                                        for (int i = 0; i < width; i += 2) {
                                            for (int j = height / 2 - 1; j >= 0; j--) {
                                                rotatedNV21[k++] = data[frameSize + j * width + i];
                                                rotatedNV21[k++] = data[frameSize + j * width + i + 1];
                                            }
                                        }
                                    }

                                    // 3. Send the UPRIGHT video to the Brain (Notice width & height are swapped!)
                                    FaceRepository.LiveFace liveFace = FaceRepository.getInstance().getLiveFaceFromNV21(rotatedNV21, height, width);

                                    // ⚡ TEMPORARILY BYPASS STRICT LIVENESS FOR DEBUGGING ⚡
                                    if (liveFace != null && liveFace.template != null) {
                                        Log.d("ArmaturaFace", "Face Detected! Liveness Score: " + liveFace.livenessScore);

                                        FaceRepository.IdentifyResult result = FaceRepository.getInstance().identify(liveFace.template);

                                        if (result != null) {
                                            Log.d("ArmaturaFace", "MATCH FOUND! PIN: " + result.pin + " Score: " + result.score);
                                            // ⚡ RAPID FIRE MODE: Do NOT freeze or stop the camera!

                                            // FIRE EVENT TO JAVASCRIPT
                                            JSObject ret = new JSObject();
                                            ret.put("pin", result.pin);
                                            ret.put("score", result.score);
                                            notifyListeners("onFaceMatched", ret);

                                            // Let JavaScript handle the grouping and decide when to close the camera!
                                        } else {
                                            Log.d("ArmaturaFace", "Face seen, but NO MATCH in database. Score too low or template missing.");
                                        }
                                    }
                                }
                            });
                        } catch (Exception e) {
                            Log.e("ArmaturaFace", "Camera start failed", e);
                        }
                    }

                    @Override
                    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
                    }

                    @Override
                    public void surfaceDestroyed(SurfaceHolder holder) {
                    }
                });

                call.resolve();
            } catch (Exception e) {
                call.reject("Failed to open camera: " + e.getMessage());
            }
        });
    }

    @PluginMethod
    public void stopCamera(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            stopCameraInternal();
            call.resolve();
        });
    }

    private void stopCameraInternal() {
        isScanning = false;

        // ⚡ RESTORE NORMAL APP BACKGROUND WHEN CAMERA CLOSES ⚡
        getActivity().runOnUiThread(() -> {
            if (getBridge() != null && getBridge().getWebView() != null) {
                getBridge().getWebView().setBackgroundColor(android.graphics.Color.parseColor("#121212"));
            }
        });

        if (mCamera != null) {
            mCamera.setPreviewCallback(null);
            mCamera.stopPreview();
            mCamera.release();
            mCamera = null;
        }
        if (cameraContainer != null) {
            cameraContainer.removeAllViews();
            cameraContainer = null;
        }
    }

    // ⚡ NEW: NATIVE HARDWARE FLASHLIGHT TOGGLE ⚡
    @PluginMethod
    public void toggleFlashlight(PluginCall call) {
        Boolean enable = call.getBoolean("enable", false);

        if (mCamera == null) {
            call.reject("Camera is not running.");
            return;
        }

        try {
            Camera.Parameters params = mCamera.getParameters();
            java.util.List<String> flashModes = params.getSupportedFlashModes();

            // Safely check if the current active camera actually has a physical flash
            if (flashModes == null) {
                call.reject("Flashlight not supported on this specific camera lens.");
                return;
            }

            if (enable && flashModes.contains(Camera.Parameters.FLASH_MODE_TORCH)) {
                params.setFlashMode(Camera.Parameters.FLASH_MODE_TORCH);
            } else if (!enable && flashModes.contains(Camera.Parameters.FLASH_MODE_OFF)) {
                params.setFlashMode(Camera.Parameters.FLASH_MODE_OFF);
            }

            mCamera.setParameters(params);

            JSObject ret = new JSObject();
            ret.put("success", true);
            call.resolve(ret);
        } catch (Exception e) {
            Log.e("ArmaturaFace", "Failed to toggle flashlight", e);
            call.reject("Exception toggling torch: " + e.getMessage());
        }
    }

    // ⚡ HELPER METHOD: Extracts the AI models to the hard drive ⚡
    private void copyModelsIfMissing(Context context) {
        String assetFolderName = "facepro_models";
        java.io.File targetDir = new java.io.File(context.getFilesDir(), "armatura_secure_v2");

        if (!targetDir.exists()) {
            targetDir.mkdirs();
        }

        try {
            String[] files = context.getAssets().list(assetFolderName);
            if (files == null || files.length == 0) {
                Log.e("ArmaturaFace", "WARNING: No .bin files found in assets/facepro_models! The engine will crash when scanning a face.");
                return;
            }

            for (String filename : files) {
                java.io.File outFile = new java.io.File(targetDir, filename);

                // Only copy if the file doesn't already exist
                if (!outFile.exists()) {
                    Log.d("ArmaturaFace", "Copying AI model: " + filename);
                    java.io.InputStream in = context.getAssets().open(assetFolderName + "/" + filename);
                    java.io.OutputStream out = new java.io.FileOutputStream(outFile);

                    byte[] buffer = new byte[1024];
                    int read;
                    while ((read = in.read(buffer)) != -1) {
                        out.write(buffer, 0, read);
                    }

                    in.close();
                    out.flush();
                    out.close();
                }
            }
            Log.d("ArmaturaFace", "All AI models are successfully staged on the disk.");
        } catch (Exception e) {
            Log.e("ArmaturaFace", "Failed to copy AI models", e);
        }
    }
    // ⚡ RESTORED: Profile Photo Extraction ⚡
    @PluginMethod
    public void extractFaceTemplate(PluginCall call) {
        if (!isEngineInitialized || !FaceRepository.getInstance().isInit()) {
            call.reject("Engine not initialized.");
            return;
        }

        String base64Image = call.getString("image");
        if (base64Image == null || base64Image.isEmpty()) {
            call.reject("Must provide a base64 'image' string.");
            return;
        }

        try {
            String pureBase64 = base64Image;
            if (base64Image.contains(",")) pureBase64 = base64Image.split(",")[1];
            android.graphics.Bitmap bitmap = android.graphics.BitmapFactory.decodeByteArray(
                    android.util.Base64.decode(pureBase64, android.util.Base64.DEFAULT), 0,
                    android.util.Base64.decode(pureBase64, android.util.Base64.DEFAULT).length);

            if (bitmap == null) {
                call.reject("Failed to decode base64 image into a Bitmap.");
                return;
            }

            byte[] templateBytes = FaceRepository.getInstance().getTemplateFromBitmap(bitmap);

            if (templateBytes != null) {
                String templateBase64 = android.util.Base64.encodeToString(templateBytes, android.util.Base64.NO_WRAP);
                JSObject ret = new JSObject();
                ret.put("template", templateBase64);
                call.resolve(ret);
            } else {
                call.reject("No face detected or extraction failed.");
            }
        } catch (Exception e) {
            call.reject("Exception during face extraction: " + e.getMessage());
        }
    }
}