import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'public_photo_disk_cache.dart';
import '../../../core/platform/uat_network_trace.dart';
import '../../../core/offline/offline_connection.dart';
import '../../../core/network/adaptive_image_policy.dart';

class PublicPhotoTransfer {
  const PublicPhotoTransfer(this.bytes, {this.downloadedBytes = 0, this.notModified = false});
  final Uint8List bytes;
  final int downloadedBytes;
  final bool notModified;
}

class PublicPhotoLoader {
  const PublicPhotoLoader(this.dio, this.disk, {this.connection});
  final Dio dio;
  final PublicPhotoDiskCache disk;
  final OfflineConnectionController? connection;

  Future<PublicPhotoTransfer> load(String url, {required CancelToken cancelToken,
    int? backgroundByteLimit, bool Function()? foregroundAttached,
    void Function(int)? onReceivedBytes, bool requirePublicResponse = false,
      bool revalidate = false}) async {
    final epoch = disk.epoch;
    final offline = connection?.current == OfflineConnection.offline;
    final small = const ['thumb', 'card', 'preview']
        .contains(Uri.tryParse(url)?.queryParameters['variant']);
    if (offline && !small)
      throw StateError(
          'لا يوجد اتصال. فتح الصور الكبيرة والتكبير يحتاجان الإنترنت.');
    var cached = await disk.read(url, allowStale: small || offline).timeout(const Duration(milliseconds: 300), onTimeout: () => null);
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (offline && cached == null && small) {
      for (final variant in const ['card', 'thumb', 'preview']) {
        cached = await disk.read(AdaptiveImagePolicy.variantUrl(url, variant),
            allowStale: true);
        if (cached != null) break;
      }
    }
    if (cached != null && small && !revalidate) {
      if (!offline &&
          connection?.current == OfflineConnection.online &&
          disk.needsValidation(url)) {
        unawaited(load(url, cancelToken: CancelToken(), revalidate: true)
            .catchError((Object _) => PublicPhotoTransfer(cached!.bytes)));
      }
      return PublicPhotoTransfer(cached.bytes, notModified: true);
    }
    if (offline) throw StateError('لا يوجد اتصال. هذه الصورة لم تُحفظ بعد.');
    final traceSequence = UatNetworkTrace.startImage(Uri.parse(dio.options.baseUrl), url);
    final traceTimer = traceSequence != null ? (Stopwatch()..start()) : null;
    final response = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes,
      headers: {if (cached != null) 'If-None-Match': cached.etag}, followRedirects: false,
      validateStatus: (status) => status == 200 || (status == 304 && cached != null) || const [401,403,404].contains(status)),
      cancelToken: cancelToken, onReceiveProgress: (received, total) {
        onReceivedBytes?.call(received);
        if (backgroundByteLimit != null && (received > backgroundByteLimit || total > backgroundByteLimit) &&
            foregroundAttached?.call() != true) {
          cancelToken.cancel('Conditional prefetch byte limit');
        }
      }).timeout(const Duration(seconds: 25), onTimeout: () {
        cancelToken.cancel('Image deadline'); throw TimeoutException('Image unavailable');
      });
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (const [401,403,404].contains(response.statusCode)) {
      await disk.forget(url);
      throw DioException.badResponse(statusCode: response.statusCode!, requestOptions: response.requestOptions, response: response);
    }
    if (!disk.accepts(response.headers)) unawaited(disk.forget(url));
    if (requirePublicResponse && !disk.accepts(response.headers) && foregroundAttached?.call() != true) {
      throw StateError('Speculative image response is not publicly cacheable');
    }
    if (traceTimer != null) {
      final measurement = UatNetworkTrace.publicImageMeasurement(
        origin: Uri.parse(dio.options.baseUrl), url: url,
        publicResponse: disk.accepts(response.headers),
        bytes: response.statusCode == 304 ? 0 : (response.data?.length ?? 0),
        elapsedMs: traceTimer.elapsedMilliseconds, status: response.statusCode ?? 0);
      if (measurement != null) UatNetworkTrace.emit({...measurement, 'seq': traceSequence!});
    }
    // A historical small preview may render immediately. Explicit full-size
    // requests still require online visibility validation.
    if (response.statusCode == 304 && cached != null) {
      return PublicPhotoTransfer(cached.bytes, notModified: true);
    }
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (bytes.isEmpty || bytes.lengthInBytes > 8 * 1024 * 1024) throw StateError('Invalid display image size');
    unawaited(disk.put(url, bytes, response.headers, expectedEpoch: epoch));
    return PublicPhotoTransfer(bytes, downloadedBytes: bytes.lengthInBytes);
  }
}
