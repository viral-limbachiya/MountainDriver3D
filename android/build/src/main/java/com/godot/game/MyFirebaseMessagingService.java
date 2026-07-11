package com.godot.game;

import android.util.Log;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class MyFirebaseMessagingService extends FirebaseMessagingService {
    private static final String TAG = "MyFirebaseMsgService";

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        Log.d(TAG, "From: " + remoteMessage.getFrom());

        String title = "";
        String body = "";

        if (remoteMessage.getNotification() != null) {
            title = remoteMessage.getNotification().getTitle();
            body = remoteMessage.getNotification().getBody();
        } else if (remoteMessage.getData().size() > 0) {
            title = remoteMessage.getData().get("title");
            body = remoteMessage.getData().get("body");
        }

        if (title != null && !title.isEmpty()) {
            Log.d(TAG, "Message Notification Title: " + title);
            Log.d(TAG, "Message Notification Body: " + body);

            FirebaseMessagingBridge bridge = FirebaseMessagingBridge.getInstance();
            if (bridge != null) {
                bridge.emitMessage(title, body);
                // Also show a local notification if they are in foreground or background,
                // so they get a visual pop up.
                bridge.showLocalNotification(title, body);
            }
        }
    }

    @Override
    public void onNewToken(String token) {
        Log.d(TAG, "Refreshed token: " + token);
        FirebaseMessagingBridge bridge = FirebaseMessagingBridge.getInstance();
        if (bridge != null) {
            bridge.emitToken(token);
        }
    }
}
