# Optional idevice dependency

The regular `GFlyerIOS` scheme builds the SwiftUI app with the preview backend.

The `GFlyerIOS-Idevice` scheme expects these locally generated files:

```text
GFlyerIOS/Vendor/idevice/include/idevice.h
GFlyerIOS/Vendor/idevice/include/module.modulemap
GFlyerIOS/Vendor/idevice/lib/libidevice_ffi.a
```

The files are intentionally not committed. Build them from the MIT-licensed `idevice` source on macOS, regenerate the Xcode project, and select the `GFlyerIOS-Idevice` scheme.
