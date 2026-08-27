import 'package:dio/dio.dart';

String friendlyApiError(Object error) {
  if (error is StateError && error.toString().contains('AUTH_REQUIRED')) {
    return 'يجب تسجيل الدخول أولاً.';
  }
  if (error is! DioException) {
    return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
  }

  final type = error.type;
  if (type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout) {
    return 'تعذر الاتصال بالخادم. تأكد من تشغيل الخدمة واتصال الهاتف ثم حاول مرة أخرى.';
  }
  if (type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout) {
    return 'استغرق الاتصال وقتاً أطول من المتوقع. حاول مرة أخرى.';
  }
  if (type == DioExceptionType.badResponse) {
    final code = error.response?.statusCode;
    final data = error.response?.data;
    final serverMessage = _serverMessage(data);
    final mappedMessage = _knownServerMessage(serverMessage);

    if (code == 401) {
      return 'انتهت جلسة الحساب أو لم يتم تسجيل الدخول.';
    }
    if (code == 403) {
      if (data is Map<String, dynamic> &&
          data['code']?.toString() == 'ACCOUNT_NOT_ACTIVE') {
        return 'تحقق من رقم الهاتف لتفعيل حسابك ثم حاول مرة أخرى.';
      }
      if (mappedMessage != null) {
        return mappedMessage;
      }
      if (_isArabic(serverMessage)) {
        return serverMessage!;
      }
      return 'ليس لديك صلاحية لتنفيذ هذه العملية.';
    }
    if (code == 404) {
      return 'لم يعد هذا المحتوى متاحاً.';
    }
    if (code == 409) {
      if (mappedMessage != null) {
        return mappedMessage;
      }
      if (_isArabic(serverMessage)) {
        return serverMessage!;
      }
      return 'تعذر إكمال العملية بسبب تعارض مع حالة حالية. حدّث الصفحة وحاول مرة أخرى.';
    }
    if (code == 422) {
      final validation = _validationMessage(data);
      if (validation != null) {
        return validation;
      }
      if (mappedMessage != null) {
        return mappedMessage;
      }
      return 'بعض البيانات غير صالحة. راجع الحقول وحاول مرة أخرى.';
    }
    if (code == 429) {
      return 'تم إرسال طلبات كثيرة خلال وقت قصير. حاول مرة أخرى بعد قليل.';
    }
    if (code != null && code >= 500) {
      return 'الخادم غير متاح مؤقتاً. حاول مرة أخرى بعد قليل.';
    }
    if (mappedMessage != null) {
      return mappedMessage;
    }
    if (_isArabic(serverMessage)) {
      return serverMessage!;
    }
    return 'تعذر إكمال الطلب. حاول مرة أخرى.';
  }
  if (type == DioExceptionType.cancel) {
    return 'تم إلغاء الطلب.';
  }
  if (type == DioExceptionType.badCertificate) {
    return 'تعذر التحقق من اتصال الخادم الآمن.';
  }
  return 'حدثت مشكلة في الاتصال. حاول مرة أخرى.';
}

String? _validationMessage(dynamic data) {
  if (data is! Map<String, dynamic>) {
    return null;
  }
  final errors = data['errors'];
  if (errors is! Map<String, dynamic>) {
    return null;
  }

  for (final entry in errors.entries) {
    final raw = entry.value;
    String? text;
    if (raw is List && raw.isNotEmpty) {
      text = raw.first?.toString().trim();
    } else {
      text = raw?.toString().trim();
    }
    final mapped = _knownServerMessage(text);
    if (mapped != null) {
      return mapped;
    }
    if (_isArabic(text)) {
      return text;
    }

    switch (entry.key) {
      case 'body':
        return 'اكتب نصاً صالحاً قبل الإرسال.';
      case 'details':
        return 'اكتب تفاصيل واضحة للبلاغ لا تقل عن 5 أحرف.';
      case 'reason':
        return 'اختر سبباً صالحاً للبلاغ.';
      case 'target_id':
      case 'target_type':
        return 'لا يمكن إرسال البلاغ على هذا المحتوى.';
      case 'property_id':
        return 'لا يمكن تنفيذ هذه العملية على الإعلان المحدد.';
      case 'advertiser':
        return 'لا يمكن تنفيذ هذه العملية على حساب المعلن المحدد.';
      case 'address':
        return 'اكتب المنطقة أو الحي الذي يقع فيه العقار.';
      case 'area_value':
      case 'area_unit':
      case 'area_m2':
        return 'أدخل مساحة العقار واختر وحدة قياس صحيحة.';
      case 'bedrooms':
        return 'أدخل عدد غرف النوم لهذا النوع من العقارات.';
      case 'bathrooms':
        return 'أدخل عدد الحمامات لهذا النوع من العقارات.';
      case 'has_parking':
        return 'حدد هل يوجد موقف سيارة أم لا.';
      case 'building_facade':
        return 'اختر واجهة البناء.';
      case 'latitude':
      case 'longitude':
        return 'حدد موقع العقار باستخدام موقعك الحالي أو الخريطة.';
    }
  }
  return null;
}

String? _serverMessage(dynamic data) {
  if (data is Map<String, dynamic>) {
    final value = data['message']?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _knownServerMessage(String? message) {
  if (message == null || message.isEmpty) {
    return null;
  }
  final lower = message.toLowerCase();
  if (lower.contains('report for this target already exists')) {
    return 'لديك بلاغ مفتوح بالفعل على هذا المحتوى. يمكنك متابعة حالته من مركز الدعم.';
  }
  if (lower.contains('complaint for this conversation already exists')) {
    return 'لديك بلاغ مفتوح بالفعل على هذه المحادثة.';
  }
  if (lower.contains('cannot report your own content') ||
      lower.contains('cannot report your own') && lower.contains('account')) {
    return 'لا يمكنك الإبلاغ عن محتوى أو حساب تملكه أنت.';
  }
  if (lower.contains('cannot start a conversation with yourself')) {
    return 'لا يمكنك بدء محادثة مع نفسك.';
  }
  if (lower.contains('cannot rate your own advertiser')) {
    return 'لا يمكنك تقييم حسابك كمعلن.';
  }
  if (lower.contains('advertiser must have a published listing')) {
    return 'لا يمكن تقييم هذا المعلن لأنه لا يملك إعلاناً منشوراً متاحاً.';
  }
  if (lower.contains('deleted comments cannot be edited')) {
    return 'لا يمكن تعديل تعليق محذوف.';
  }
  if (lower.contains('only active complaints can authorize')) {
    return 'هذا البلاغ مغلق ولم يعد يسمح بفتح محتوى المحادثة.';
  }
  if (lower
      .contains('official broker verification is required before approval')) {
    return 'يجب طلب تحقق الدلال الرئيسي وانتظار رده قبل اعتماد الإعلان.';
  }
  if (lower.contains('official broker verification is still pending')) {
    return 'طلب تحقق الدلال الرئيسي ما زال بانتظار الرد.';
  }
  if (lower.contains('official broker has not confirmed')) {
    return 'لا يمكن اعتماد الإعلان لأن الدلال الرئيسي لم يؤكد أن العقار متاح.';
  }
  if (lower.contains('broker verification request is already pending')) {
    return 'يوجد طلب تحقق مفتوح بالفعل لهذا الإعلان.';
  }
  if (lower.contains('official broker assignment changed')) {
    return 'تغير الدلال الرئيسي للمربع. اطلب تحققاً جديداً من الدعم.';
  }
  if (lower.contains('broker verification request is already closed')) {
    return 'تم إغلاق طلب التحقق هذا بالفعل.';
  }
  if (lower.contains('not the assigned broker for this verification')) {
    return 'طلب التحقق هذا ليس تابعاً لمربعك الحالي.';
  }
  if (lower.contains('official broker verification is not required')) {
    return 'هذا الإعلان لا يحتاج تحقق الدلال الرئيسي.';
  }
  return null;
}

bool _isArabic(String? value) {
  return value != null && RegExp(r'[\u0600-\u06FF]').hasMatch(value);
}
