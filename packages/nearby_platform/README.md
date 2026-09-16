# nearby_platform

Flutter platform adapters for MeowWatch Nearby. This package connects the pure
Dart `nearby_bridge` protocol to protected credential storage and DNS-SD/mDNS.

## Protected storage

Create one `ProtectedNearbyStore` per app data profile and share that instance
between the desktop authority, identity owner, and phone client store view. The
caller supplies the lowercase SHA-256 hex digest of its resolved
`MEOWWATCH_DATA_DIR` namespace. The path itself is never stored.

The store replaces one versioned JSON document through
`flutter_secure_storage`. Mutations for one namespace are serialized in the
current isolate, revocation tombstones are durable, and malformed documents
fail with `storage_corrupt`; there is no file, preferences, or in-memory
production fallback. The document contains the TLS private key and pairing
secrets, so callers must treat storage failures as a terminal Nearby error.
`listPairedDevices` returns public metadata only.
`listClientCredentials` is bounded to 64 entries for the app's paired-desktop
fallback; credential `toString` is redacted and UI must use only safe fields.

Android integration must disable backup or exclude Flutter Secure Storage's
preferences as described by that plugin. Native configuration belongs to the
embedding app.

## mDNS

`NearbyAdvertisementRegistration` publishes only `_meowwatch._tcp` with TXT
keys `v`, `id`, `pairing`, and bounded `name`. `NearbyDiscovery` exposes address
and host values as untrusted hints: callers still validate the numeric address
against the selected LAN interface and authenticate the pinned TLS peer.

Registration and discovery own only the plugin handles they receive. Calling
`stop` while `start` is pending cancels the start and cleans that eventual
handle once. Permission failures surface as `permission_denied`; they are never
reported as a successful empty scan.
