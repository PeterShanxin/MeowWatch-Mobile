# Nearby Android runtime gate

`run.py` launches one prebuilt integration APK in three distinct Android
processes without uninstalling or clearing the package between stages. Flutter
3.44's `--keep-app-running` skips the driver's normal uninstall; the runner then
owns an explicit `am force-stop`, verifies the PID is gone, verifies the package
is still installed, and starts the next stage through `adb install -t -r`.

The device test uses the production `FlutterSecureStorage`, Android LAN method
channel and `nsd` plugin. Artifacts contain booleans, counts, interface labels,
prefix lengths and mDNS service metadata. They intentionally exclude protected
documents, token IDs, secrets, private keys, certificate PEM and numeric local
addresses. A self-advertisement may be observed, but the gate never claims that
a Windows desktop was discovered or paired.
