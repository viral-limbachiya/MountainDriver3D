package com.godot.game;

import android.app.Activity;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.messaging.FirebaseMessaging;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.HashSet;
import java.util.Set;

public class FirebaseMessagingBridge extends GodotPlugin {
    private static final String TAG = "FirebaseMessagingBridge";
    private static FirebaseMessagingBridge instance;
    private final Activity activity;

    public FirebaseMessagingBridge(Godot godot) {
        super(godot);
        this.activity = godot.getActivity();
        instance = this;
        createNotificationChannel();
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "FirebaseMessagingBridge";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("fcm_token_received", String.class));
        signals.add(new SignalInfo("notification_received", String.class, String.class));
        signals.add(new SignalInfo("notification_opened", String.class, String.class));
        return signals;
    }

    public static FirebaseMessagingBridge getInstance() {
        return instance;
    }

    @UsedByGodot
    public void get_fcm_token() {
        if (activity == null) return;
        
        try {
            FirebaseMessaging.getInstance().getToken()
                .addOnCompleteListener(new OnCompleteListener<String>() {
                    @Override
                    public void onComplete(@NonNull Task<String> task) {
                        if (!task.isSuccessful()) {
                            Log.w(TAG, "Fetching FCM registration token failed", task.getException());
                            return;
                        }
                        String token = task.getResult();
                        Log.d(TAG, "FCM Token: " + token);
                        emitToken(token);
                    }
                });
        } catch (Exception e) {
            Log.e(TAG, "Error getting token: " + e.getMessage());
        }
    }

    @UsedByGodot
    public void subscribe_to_topic(String topic) {
        try {
            FirebaseMessaging.getInstance().subscribeToTopic(topic);
            Log.d(TAG, "Subscribed to topic: " + topic);
        } catch (Exception e) {
            Log.e(TAG, "Failed to subscribe to topic: " + e.getMessage());
        }
    }

    public void emitToken(final String token) {
        if (activity != null) {
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    emitSignal("fcm_token_received", token);
                }
            });
        }
    }

    public void emitMessage(final String title, final String body) {
        if (activity != null) {
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    emitSignal("notification_received", title, body);
                }
            });
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (activity == null) return;
            CharSequence name = "Default Channel";
            String description = "Channel for game push notifications";
            int importance = NotificationManager.IMPORTANCE_DEFAULT;
            NotificationChannel channel = new NotificationChannel("game_notifications", name, importance);
            channel.setDescription(description);
            NotificationManager notificationManager = activity.getSystemService(NotificationManager.class);
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }
        }
    }

    public void showLocalNotification(String title, String body) {
        if (activity == null) return;

        Intent intent = new Intent(activity, activity.getClass());
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        intent.putExtra("notification_title", title);
        intent.putExtra("notification_body", body);

        // FLAG_IMMUTABLE is required for API 31+
        PendingIntent pendingIntent = PendingIntent.getActivity(activity, 0, intent,
                PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE);

        NotificationCompat.Builder notificationBuilder =
                new NotificationCompat.Builder(activity, "game_notifications")
                        .setSmallIcon(android.R.drawable.stat_notify_chat)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setAutoCancel(true)
                        .setContentIntent(pendingIntent);

        NotificationManager notificationManager =
                (NotificationManager) activity.getSystemService(Context.NOTIFICATION_SERVICE);

        if (notificationManager != null) {
            notificationManager.notify(0, notificationBuilder.build());
        }
    }
}
