package com.tnaafrica.fieldapp;

import android.Manifest;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    private static final int STARTUP_PERMISSIONS_REQUEST = 1;
    // Ask for All Files Access once per app start, so coming back from Settings without it does not loop
    private boolean allFilesAccessAsked = false;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Register the custom plugin
       registerPlugin(ArmaturaFacePlugin.class);
        registerPlugin(AppUpdaterPlugin.class);
        super.onCreate(savedInstanceState);

        // ⚡ NEW: Immediately request GPS and Camera permissions on startup
        ActivityCompat.requestPermissions(this, new String[]{
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.CAMERA
        }, STARTUP_PERMISSIONS_REQUEST);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        // ⚡ Ask for All Files Access only after the GPS/Camera popup closes, so the two do not hide each other
        if (requestCode == STARTUP_PERMISSIONS_REQUEST) askAllFilesAccessOnStartup();
    }

    // ⚡ NEW: The Armatura face SDK needs 'All Files Access' (Android 11+). Ask at start-up, not on the first face scan.
    // AUTO-HEAL: if it is skipped here, ArmaturaFacePlugin.initEngine() still asks on the first face scan, as before.
    private void askAllFilesAccessOnStartup() {
        if (allFilesAccessAsked || isFinishing()) return;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return;
        if (Environment.isExternalStorageManager()) return;
        allFilesAccessAsked = true;

        new AlertDialog.Builder(this)
                .setTitle("Allow All Files Access")
                .setMessage("The face scanner needs 'All Files Access' to load its license.\n\nOn the next screen switch ON 'Allow access to manage all files', then come back to the app.")
                .setCancelable(false)
                .setPositiveButton("Open Settings", (dialog, which) -> openAllFilesAccessSettings())
                .setNegativeButton("Later", null)
                .show();
    }

    private void openAllFilesAccessSettings() {
        try {
            Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        } catch (Exception e) {
            // AUTO-HEAL: some Android builds have no per-app screen - open the list of all apps instead
            try {
                startActivity(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
            } catch (Exception e2) {
                Log.w("MainActivity", "Could not open All Files Access settings", e2);
            }
        }
    }
}
