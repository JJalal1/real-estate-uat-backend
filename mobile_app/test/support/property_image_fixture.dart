import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';

/// Deterministic original pixel fixture, only in tests. No network or app assets.
Future<void> withPropertyImageFixture(Future<void> Function() body, {int statusCode = 200}) async {
  final previous = debugNetworkImageHttpClientProvider;
  debugNetworkImageHttpClientProvider = () => _ImageClient(statusCode);
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = previous;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

/// Run inside tester.runAsync so the engine can finish decoding before capture.
Future<void> decodePropertyImageFixtures(List<String> urls) async {
  for (final url in urls) {
    final complete = Completer<void>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((image, synchronous) {
      image.dispose();
      if (!complete.isCompleted) complete.complete();
    }, onError: (Object error, StackTrace? stack) {
      if (!complete.isCompleted) complete.completeError(error, stack);
    });
    stream.addListener(listener);
    try {
      await complete.future;
    } finally {
      stream.removeListener(listener);
    }
  }
}

final _pixels = base64Decode('iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAYAAACbU/80AAADi0lEQVR4nBXOYQeGBgIA4Psb44iIiIiIiIiIiIhcREQul8uyjDHGGGOMMY5jjDGO+4t3z/vh+f785Yu//+1/fyUgJCImISUjp6CkoqahpaNnYGRiZmFlY+fg5OLm4eUvX/xDgICQiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uH9x+fwD8FCAiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uHl4//kJfClAQEhETEJKRk5BSUVNQ0tHz8DIxMzCysbOwcnFzcP75SfwlQABIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3D+9Xn8DXAgSERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw8vF9/At8IEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPwfvMJfCtAQEhETEJKRk5BSUVNQ0tHz8DIxMzCysbOwcnFzcP77SfwnQABIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3D+93n8D3AgSERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw8vN9/Aj8IEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPw/vAJ/ChAQEhETEJKRk5BSUVNQ0tHz8DIxMzCysbOwcnFzcP74yfwkwABIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3D+9Pn8DPAgSERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw8vD9/Ar8IEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPw/vIJ/CpAQEhETEJKRk5BSUVNQ0tHz8DIxMzCysbOwcnFzcP76yfwLwECQiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uHt5/fQL/FiAgJCImISUjp6CkoqahpaNnYGRiZmFlY+fg5OLm4f33J/CbAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP72+fwO8CBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8v38CfwgQEBIRk5CSkVNQUlHT0NLRMzAyMbOwsrFzcHJx8/D+8Qn8KUBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw/vnJ/AfAQJCImISUjJyCkoqahpaOnoGRiZmFlY2dg5OLm4e3v98Av8VICAkIiYhJSOnoKSipqGlo2dgZGJmYWVj5+Dk4ubh5f9B2IRbefXERAAAAABJRU5ErkJggg==');

class _ImageClient implements HttpClient {
  _ImageClient(this.statusCode);
  final int statusCode;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(statusCode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.statusCode);
  final int statusCode;
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(statusCode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.statusCode);
  @override
  final int statusCode;
  @override
  int get contentLength => _pixels.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {
    Function? onError, void Function()? onDone, bool? cancelOnError,
  }) => Stream<List<int>>.value(_pixels).listen(onData,
      onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
