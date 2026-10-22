# idevice

The `GFlyerPublic` scheme builds the app with the preview backend and runs in
the iOS Simulator without anything in this folder.

The `GFlyerPublic-Idevice` scheme, which controls the location of a real
iPhone, links these locally generated files:

```text
GFlyerIOS/Vendor/idevice/include/idevice.h
GFlyerIOS/Vendor/idevice/include/module.modulemap
GFlyerIOS/Vendor/idevice/lib/libidevice_ffi.a
```

They are not committed. On a Mac with Xcode and Rust, run
`scripts/build_idevice.sh`: it builds them from the MIT-licensed `idevice`
source at a pinned revision and copies them here. Then run `xcodegen generate`
and select the `GFlyerPublic-Idevice` scheme.
