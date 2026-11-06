package com.dinecircle.dine_circle

// flutter_stripe's PaymentSheet requires a FlutterFragmentActivity (it hosts
// native Stripe UI via support fragments); FlutterActivity would crash on
// present. Pair with the AppCompat-descendant themes in res/values/styles.
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
