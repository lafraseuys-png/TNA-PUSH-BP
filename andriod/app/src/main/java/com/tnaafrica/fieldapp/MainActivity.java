package com.tnaafrica.fieldapp;

import android.Manifest;
import android.os.Bundle;
import androidx.core.app.ActivityCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Register the custom plugin
        registerPlugin(ArmaturaFacePlugin.class);
        super.onCreate(savedInstanceState);

        // ⚡ NEW: Immediately request GPS and Camera permissions on startup
        ActivityCompat.requestPermissions(this, new String[]{
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.CAMERA
        }, 1);
    }
}