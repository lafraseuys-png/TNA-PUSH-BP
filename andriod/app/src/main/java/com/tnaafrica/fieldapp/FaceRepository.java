package com.tnaafrica.fieldapp;

import android.content.Context;
import android.util.Log;

import com.armatura.facepro.AMTFaceProService;
import com.armatura.facepro.ver56.auth.FaceAuthNative;

import java.nio.ByteBuffer;
import android.graphics.Bitmap;

public class FaceRepository {
    private static final String TAG = "FaceRepository";
    private static FaceRepository instance;
    private long faceEngineContext = 0;
    private boolean isInit = false;

    // Small helper class to hold the live face data
    public static class LiveFace {
        public byte[] template;
        public int livenessScore;
    }

    // Small helper class to hold the match result
    public static class IdentifyResult {
        public String pin;
        public int score;

        public IdentifyResult(String pin, int score) {
            this.pin = pin;
            this.score = score;
        }
    }

    private FaceRepository() { }

    public static FaceRepository getInstance() {
        if (instance == null) {
            synchronized (FaceRepository.class) {
                if (instance == null) {
                    instance = new FaceRepository();
                }
            }
        }
        return instance;
    }

    public boolean isInit() {
        return this.isInit;
    }

    // ⚡ 1. ENGINE BOOT ⚡
    public boolean init(Context application) {
        if (this.isInit && this.faceEngineContext != 0) {
            return true;
        }

        long[] finalContext = new long[1];
        int initRet = AMTFaceProService.init(application, finalContext);
        Log.i(TAG, "Engine Init Result = " + initRet);

        if (initRet == 0 && finalContext[0] != 0) {
            this.faceEngineContext = finalContext[0];
            AMTFaceProService.dbClear(this.faceEngineContext);
            this.isInit = true;
            return true;
        }
        this.isInit = false;
        return false;
    }

    // ⚡ 2. HIGH-SPEED NV21 DETECTION & LIVENESS ⚡
    public LiveFace getLiveFaceFromNV21(byte[] nv21, int width, int height) {
        if (!isInit || faceEngineContext == 0) return null;

        int[] faceCount = new int[1];
        // Scan the raw video frame
        if (AMTFaceProService.detectFacesFromNV21(this.faceEngineContext, nv21, width, height, faceCount) != 0 || faceCount[0] <= 0) {
            return null;
        }

        long[] faceContext = new long[1];
        // Grab the first face found
        if (AMTFaceProService.getFaceContext(this.faceEngineContext, 0, faceContext) != 0) {
            return null;
        }

        LiveFace liveFace = new LiveFace();

        // Check Liveness (Anti-Spoofing)
        int[] liveness = new int[1];
        if (AMTFaceProService.getLiveness(faceContext[0], liveness) == 0) {
            liveFace.livenessScore = liveness[0];
            // If it's a photo or a spoof, you can reject it here. Usually, a score > 0 is a real person.
            // If liveness == 0, it might be a spoof. We will still extract it, but log it.
            Log.d(TAG, "Liveness Score: " + liveFace.livenessScore);
        }

        // Extract the 256-byte Template
        byte[] templateBytes = new byte[256];
        if (AMTFaceProService.extractTemplate(faceContext[0], templateBytes, new int[]{256}, new int[1]) == 0) {
            liveFace.template = templateBytes;
            return liveFace;
        }

        return null;
    }

    // ⚡ 3. 1:N IDENTIFICATION ⚡
    public IdentifyResult identify(byte[] liveTemplate) {
        if (!isInit || faceEngineContext == 0 || liveTemplate == null) return null;

        int[] matchScore = new int[1];
        int[] matchResult = new int[1];
        byte[] matchedPinBytes = new byte[256];

        // 70 is the minimum confidence score (out of 100)
        int identifyRet = AMTFaceProService.dbIdentify(this.faceEngineContext, liveTemplate, matchedPinBytes, matchScore, matchResult, new int[]{1}, 70, 100);

        if (identifyRet == 0 && matchScore[0] >= 70) {
            String matchedPin = new String(matchedPinBytes).trim();
            return new IdentifyResult(matchedPin, matchScore[0]);
        }

        return null;
    }

    // ⚡ 4. RAM DATABASE MANAGEMENT ⚡
    public boolean dbAdd(String pin, byte[] template) {
        if (!isInit || faceEngineContext == 0) return false;
        return AMTFaceProService.dbAdd(this.faceEngineContext, pin, template) == 0;
    }

    public boolean dbClear() {
        if (!isInit || faceEngineContext == 0) return false;
        return AMTFaceProService.dbClear(this.faceEngineContext) == 0;
    }

    public int dbCount() {
        if (!isInit || faceEngineContext == 0) return 0;
        int[] count = new int[1];
        if (AMTFaceProService.dbCount(this.faceEngineContext, count) == 0) {
            return count[0];
        }
        return 0;
    }

    // ⚡ 5. STATIC IMAGE EXTRACTION (For Web App Profile Photos) ⚡
    public byte[] getTemplateFromBitmap(Bitmap bitmap) {
        if (!isInit || faceEngineContext == 0 || bitmap == null) return null;

        int[] faceCount = new int[1];
        if (AMTFaceProService.detectFacesFromBitmap(this.faceEngineContext, bitmap, faceCount) != 0 || faceCount[0] <= 0) {
            return null;
        }

        long[] faceContext = new long[1];
        if (AMTFaceProService.getFaceContext(this.faceEngineContext, 0, faceContext) != 0) {
            return null;
        }

        byte[] templateBytes = new byte[256];
        if (AMTFaceProService.extractTemplate(faceContext[0], templateBytes, new int[]{256}, new int[1]) == 0) {
            return templateBytes;
        }
        return null;
    }
}