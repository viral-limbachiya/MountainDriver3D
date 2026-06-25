package com.godot.game;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import androidx.annotation.NonNull;
import com.google.firebase.analytics.FirebaseAnalytics;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

public class FirebaseAnalyticsBridge extends GodotPlugin {
    private FirebaseAnalytics mFirebaseAnalytics;
    private final Activity activity;

    public FirebaseAnalyticsBridge(Godot godot) {
        super(godot);
        this.activity = godot.getActivity();
        if (activity != null) {
            try {
                // Initialize Firebase Analytics safely (will fail gracefully if google-services.json is missing)
                mFirebaseAnalytics = FirebaseAnalytics.getInstance(activity);
                Log.i("FirebaseAnalyticsBridge", "Firebase Analytics initialized successfully");
            } catch (Exception e) {
                Log.e("FirebaseAnalyticsBridge", "Failed to initialize Firebase Analytics: " + e.getMessage());
            }
        }
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "FirebaseAnalyticsBridge";
    }

    @UsedByGodot
    public void log_event(String name, org.godotengine.godot.Dictionary params) {
        if (mFirebaseAnalytics == null) {
            Log.w("FirebaseAnalyticsBridge", "Firebase Analytics is not initialized. Event ignored: " + name);
            return;
        }
        Bundle bundle = new Bundle();
        if (params != null) {
            for (String key : params.keySet()) {
                Object value = params.get(key);
                if (value instanceof String) {
                    bundle.putString(key, (String) value);
                } else if (value instanceof Integer || value instanceof Long) {
                    bundle.putLong(key, ((Number) value).longValue());
                } else if (value instanceof Double || value instanceof Float) {
                    bundle.putDouble(key, ((Number) value).doubleValue());
                } else if (value instanceof Boolean) {
                    bundle.putBoolean(key, (Boolean) value);
                }
            }
        }
        mFirebaseAnalytics.logEvent(name, bundle);
    }
}
