# DineCircle — v1.0.0 (versionCode 1)

App version : 1.0.0+1
Package     : com.dinecircle.dine_circle
Built       : 26 Oct 2026, 21:47 (release, debug-key signed — sideload OK, not for Play Store)
Server      : http://192.168.100.70:4000/api (LAN dev server baked in)

## Files

- DineCircle-v1.0.0-arm64-v8a.apk   <- INSTALL THIS on almost all modern phones
- DineCircle-v1.0.0-armeabi-v7a.apk <- only for older 32-bit budget phones

## Install

1. Uninstall any older DineCircle app from the phone first (old builds
   point at a dead server address).
2. Copy DineCircle-v1.0.0-arm64-v8a.apk to the phone and tap it.
   Allow "install from unknown sources" if prompted.
3. Phone and laptop must be on the SAME Wi-Fi, and the laptop's API +
   database must be running.

## If the app says "No connection. Check your network and try again."

Open in phone Chrome: http://192.168.100.70:4000/
- Error text appears  -> network fine, you installed an old APK -> redo step 1.
- Page times out      -> same-Wi-Fi / router client-isolation problem.
