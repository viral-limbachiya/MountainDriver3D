package com.godot.game;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.annotation.NonNull;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.AdView;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.initialization.InitializationStatus;
import com.google.android.gms.ads.initialization.OnInitializationCompleteListener;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAd;
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAdLoadCallback;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;

import java.util.Collections;
import java.util.Set;
import java.util.HashSet;

public class AdMobBridge extends GodotPlugin {
    private final Activity activity;
    private AdView adView;
    private RewardedAd rewardedAd;
    private RewardedInterstitialAd rewardedInterstitialAd;
    private boolean isBannerLoaded = false;
    private boolean isRewardedLoaded = false;
    private boolean isRewardedInterstitialLoaded = false;

    public AdMobBridge(Godot godot) {
        super(godot);
        this.activity = godot.getActivity();
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "AdMobBridge";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("admob_initialized"));
        signals.add(new SignalInfo("rewarded_ad_loaded"));
        signals.add(new SignalInfo("rewarded_ad_failed_to_load", Integer.class));
        signals.add(new SignalInfo("user_earned_reward", String.class, Integer.class));
        signals.add(new SignalInfo("rewarded_ad_dismissed"));
        signals.add(new SignalInfo("rewarded_interstitial_loaded"));
        signals.add(new SignalInfo("rewarded_interstitial_failed_to_load", Integer.class));
        signals.add(new SignalInfo("rewarded_interstitial_dismissed"));
        return signals;
    }

    public void initialize_admob() {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                MobileAds.initialize(activity, new OnInitializationCompleteListener() {
                    @Override
                    public void onInitializationComplete(@NonNull InitializationStatus initializationStatus) {
                        emitSignal("admob_initialized");
                    }
                });
            }
        });
    }

    public void load_banner(final String adUnitId, final boolean atTop) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (adView != null) {
                    ViewGroup parent = (ViewGroup) adView.getParent();
                    if (parent != null) {
                        parent.removeView(adView);
                    }
                    adView.destroy();
                }

                adView = new AdView(activity);
                adView.setAdUnitId(adUnitId);
                adView.setAdSize(AdSize.BANNER);

                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT
                );
                params.gravity = atTop ? Gravity.TOP | Gravity.CENTER_HORIZONTAL : Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;

                ViewGroup root = (ViewGroup) activity.getWindow().getDecorView().findViewById(android.R.id.content);
                root.addView(adView, params);

                AdRequest adRequest = new AdRequest.Builder().build();
                adView.loadAd(adRequest);
                isBannerLoaded = true;
            }
        });
    }

    public void show_banner() {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (adView != null) {
                    adView.setVisibility(View.VISIBLE);
                }
            }
        });
    }

    public void hide_banner() {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (adView != null) {
                    adView.setVisibility(View.GONE);
                }
            }
        });
    }

    public void load_rewarded(final String adUnitId) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                isRewardedLoaded = false;
                AdRequest adRequest = new AdRequest.Builder().build();
                RewardedAd.load(activity, adUnitId, adRequest, new RewardedAdLoadCallback() {
                    @Override
                    public void onAdFailedToLoad(@NonNull LoadAdError loadAdError) {
                        rewardedAd = null;
                        emitSignal("rewarded_ad_failed_to_load", loadAdError.getCode());
                    }

                    @Override
                    public void onAdLoaded(@NonNull RewardedAd ad) {
                        rewardedAd = ad;
                        isRewardedLoaded = true;
                        emitSignal("rewarded_ad_loaded");
                    }
                });
            }
        });
    }

    public void show_rewarded() {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (rewardedAd != null) {
                    rewardedAd.setFullScreenContentCallback(new FullScreenContentCallback() {
                        @Override
                        public void onAdDismissedFullScreenContent() {
                            rewardedAd = null;
                            isRewardedLoaded = false;
                            emitSignal("rewarded_ad_dismissed");
                        }

                        @Override
                        public void onAdFailedToShowFullScreenContent(@NonNull AdError adError) {
                            rewardedAd = null;
                            isRewardedLoaded = false;
                        }
                    });
                    rewardedAd.show(activity, reward -> emitSignal("user_earned_reward", reward.getType(), reward.getAmount()));
                }
            }
        });
    }

    public void load_rewarded_interstitial(final String adUnitId) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                isRewardedInterstitialLoaded = false;
                AdRequest adRequest = new AdRequest.Builder().build();
                RewardedInterstitialAd.load(activity, adUnitId, adRequest, new RewardedInterstitialAdLoadCallback() {
                    @Override
                    public void onAdFailedToLoad(@NonNull LoadAdError loadAdError) {
                        rewardedInterstitialAd = null;
                        emitSignal("rewarded_interstitial_failed_to_load", loadAdError.getCode());
                    }

                    @Override
                    public void onAdLoaded(@NonNull RewardedInterstitialAd ad) {
                        rewardedInterstitialAd = ad;
                        isRewardedInterstitialLoaded = true;
                        emitSignal("rewarded_interstitial_loaded");
                    }
                });
            }
        });
    }

    public void show_rewarded_interstitial() {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (rewardedInterstitialAd != null) {
                    rewardedInterstitialAd.setFullScreenContentCallback(new FullScreenContentCallback() {
                        @Override
                        public void onAdDismissedFullScreenContent() {
                            rewardedInterstitialAd = null;
                            isRewardedInterstitialLoaded = false;
                            emitSignal("rewarded_interstitial_dismissed");
                        }

                        @Override
                        public void onAdFailedToShowFullScreenContent(@NonNull AdError adError) {
                            rewardedInterstitialAd = null;
                            isRewardedInterstitialLoaded = false;
                        }
                    });
                    rewardedInterstitialAd.show(activity, reward -> emitSignal("user_earned_reward", reward.getType(), reward.getAmount()));
                }
            }
        });
    }

    public boolean is_rewarded_loaded() {
        return isRewardedLoaded;
    }

    public boolean is_rewarded_interstitial_loaded() {
        return isRewardedInterstitialLoaded;
    }
}
