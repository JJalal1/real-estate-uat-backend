# تجهيز بناء Android لمتطلبات API 36 — 25 أكتوبر 2026

## العائق المثبت

يستخدم المشروع Flutter 3.27.3، وفي مصدر هذه النسخة الرسمي `compileSdkVersion=35` و`targetSdkVersion=35`. كان Gradle الخاص بالتطبيق يرث هاتين القيمتين. تنص متطلبات Google Play الحالية، السارية من 31 أغسطس 2026، على API 36 للتطبيقات الجديدة وتحديثاتها. لذلك لا يثبت نجاح APK UAT السابق أهلية رفعه للمتجر.

## التغيير المحدود

- تثبيت compile/target على API 36، مع الحفاظ على minSdk 23.
- Android Gradle Plugin 8.10.1 مع Gradle 8.11.1، وهما متوافقان رسميًا مع API 36 وJDK 17. ثُبت SHA256 لتوزيعة Gradle من المرجع الرسمي.
- تبقى نسخة Flutter وحزم Dart وهوية التطبيق وطرق الصلاحيات والأصول وقواعد التوقيع كما هي.
- يتحقق فاحص APK الفعلي من target SDK وmin SDK، ومن محاذاة PT_LOAD لكل مكتبات arm64-v8a وx86_64 على 16KB، و`zipalign -P 16`، إلى جانب فحوص المصدر والتوقيع والبايتات والأصول القائمة.

لا يكفي أن تعلن ملفات الإعداد هذه القيم؛ يلزم نجاح البناء وفحص الحزمة الناتجة على SHA هذا التغيير قبل الدمج. كما يلزم لاحقًا اختبار الجهاز، وخاصة insets/edge-to-edge والأذونات والكاميرا/الموقع والروابط وتحديث نسخة قديمة وبيئة صفحات ذاكرة 16KB. نجاح فحص ELF/ZIP لا يساوي اختبار تشغيل جهاز 16KB.

## المصادر الأولية التي فُحصت في هذه المهمة

- [Google Play: target API requirements](https://developer.android.com/google/play/requirements/target-sdk).
- [Android Gradle Plugin 8.10 compatibility](https://developer.android.com/build/releases/agp-8-10-0-release-notes).
- [Gradle official checksums — 8.11.1](https://gradle.org/release-checksums/): `f397b287023acdba1e9f6fc5ea72d22dd63669d59ed4a289a29b1a76eee151c6`.
- [Android 16KB page sizes](https://developer.android.com/guide/practices/page-sizes).
- [Flutter 3.27.3 official Gradle defaults](https://github.com/flutter/flutter/blob/3.27.3/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy).

إعداد Production منفصل، وهوية رسمية وتوقيع AAB وApp Links ومزودا OTP/FCM وسياسة المتجر وموافقة الإطلاق، كلها بوابات مستقلة لا تُعتمد بهذا التغيير.
