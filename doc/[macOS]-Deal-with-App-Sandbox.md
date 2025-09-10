# macOS App Sandbox Configuration

For macOS, Flutter app restricts its capability by enabling [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) by default. You can change the behavior by editing your app's entitlements files depending on your configuration.

- [`macos/Runner/Release.entitlements`](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx/example/viewer/macos/Runner/Release.entitlements)
- [`macos/Runner/DebugProfile.entitlements`](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx/example/viewer/macos/Runner/DebugProfile.entitlements)

#### Deal with App Sandbox

The easiest option to access files on your local storage (i.e. SSD or HDD), set [`com.apple.security.app-sandbox`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_app-sandbox) to false on your entitlements file though it is not recommended for releasing apps because it completely disables [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox).

Another option is to use [`com.apple.security.files.user-selected.read-only`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_user-selected_read-only) along with [file_selector_macos](https://pub.dev/packages/file_selector_macos). The option is better in security than the previous option.

Anyway, the example code for the plugin illustrates how to download and preview internet hosted PDF file. It uses
[`com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_network_client) along with [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager):

```xml
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
```