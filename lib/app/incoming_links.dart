import 'dart:async';

import 'package:app_links/app_links.dart';

/// Narrow seam around [AppLinks] so OS delivery can be exercised without a
/// platform channel in widget tests.
abstract interface class IncomingLinkSource {
  Future<Uri?> getInitialLink();

  Stream<Uri> get uriLinkStream;
}

final class AppLinksIncomingLinkSource implements IncomingLinkSource {
  AppLinksIncomingLinkSource() : _appLinks = AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;
}

typedef IncomingLinkCallback = void Function(Uri uri);
typedef IncomingLinkErrorCallback = void Function(Object error);

/// Owns cold- and warm-link delivery for the lifetime of the app widget.
final class IncomingLinks {
  IncomingLinks(this._source);

  final IncomingLinkSource _source;
  StreamSubscription<Uri>? _subscription;
  bool _closed = false;

  Future<void> start({
    required IncomingLinkCallback onLink,
    required IncomingLinkErrorCallback onError,
  }) async {
    if (_closed || _subscription != null) return;
    var loadingInitial = true;
    final queuedWarmLinks = <Uri>[];

    void deliver(Uri uri) {
      if (_closed) return;
      onLink(uri);
    }

    _subscription = _source.uriLinkStream.listen(
      (uri) {
        if (loadingInitial) {
          queuedWarmLinks.add(uri);
        } else {
          deliver(uri);
        }
      },
      onError: (Object error, StackTrace _) {
        if (!_closed) onError(error);
      },
    );

    try {
      final initial = await _source.getInitialLink();
      if (initial != null) deliver(initial);
    } catch (error) {
      if (!_closed) onError(error);
    } finally {
      loadingInitial = false;
      for (final uri in queuedWarmLinks) {
        deliver(uri);
      }
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
