import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/platform/stage5_media_picker.dart';

enum ListingPhotoIssue {
  mismatch('الصورة غير مطابقة. أرفق صورة مناسبة للعقار.'),
  invalidFile('اختر صورة JPG أو PNG أو WebP حتى 8 ميجابايت.'),
  unavailable('تعذّر فحص الصورة. أعد المحاولة.');

  const ListingPhotoIssue(this.message);
  final String message;
}

class ListingPhotoCheck {
  const ListingPhotoCheck();

  static const _structure = {
    'building',
    'roof',
    'skyscraper',
    'room',
    'kitchen',
    'bedroom',
    'bathroom',
  };
  static const _land = {'soil', 'field', 'prairie'};
  static const _farm = {'farm', 'ranch', 'barn', 'field', 'soil', 'garden'};
  static const _unrelated = {
    'car',
    'vehicle',
    'motorcycle',
    'van',
    'tire',
    'selfie',
    'passport',
    'receipt',
    'web page',
    'screenshot',
    'food',
    'dog',
    'pet',
  };

  bool matches(Map<String, double> labels, String propertyType) {
    final typeLabels = switch (propertyType) {
      'land' => _land,
      'farm' => _farm,
      'apartment' ||
      'floor' ||
      'building' ||
      'house' ||
      'villa' ||
      'shop' ||
      'office' =>
        _structure,
      _ => const <String>{},
    };
    final confidence = _score(labels, typeLabels);
    final unrelated = _score(labels, _unrelated);
    final otherScene = switch (propertyType) {
      'land' => _score(labels, _structure),
      'farm' => 0.0,
      _ => _score(labels, _land),
    };
    return confidence >= 0.55 &&
        unrelated < confidence + 0.08 &&
        otherScene < confidence + 0.12;
  }

  double _score(Map<String, double> labels, Set<String> candidates) {
    var highest = 0.0;
    for (final label in candidates) {
      final score = labels[label] ?? 0;
      if (score > highest && score <= 1) highest = score;
    }
    return highest;
  }

  Future<ListingPhotoIssue?> validate(String path, String propertyType) async {
    try {
      final labels = await const Stage5MediaPicker()
          .labelListingPhoto(path)
          .timeout(const Duration(seconds: 20));
      if (!matches(labels, propertyType)) return ListingPhotoIssue.mismatch;
    } on PlatformException catch (error) {
      return error.code == 'LISTING_PHOTO_UNREADABLE'
          ? ListingPhotoIssue.invalidFile
          : ListingPhotoIssue.unavailable;
    } on MissingPluginException {
      return ListingPhotoIssue.unavailable;
    } on TimeoutException {
      return ListingPhotoIssue.unavailable;
    }

    final extension = path.split('.').last.toLowerCase();
    try {
      if (!const ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ||
          File(path).lengthSync() > 8 * 1024 * 1024) {
        return ListingPhotoIssue.invalidFile;
      }
    } on FileSystemException {
      return ListingPhotoIssue.invalidFile;
    }
    return null;
  }
}
