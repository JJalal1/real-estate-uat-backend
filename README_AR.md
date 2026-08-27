# REAL ESTATE — UAT Mobile GitHub Build V1.0

هذه الحزمة لا تعمل على جهازك ولا تحتوي BAT أو PowerShell.

الغرض منها: إضافة مصدر Flutter الحالي إلى نفس مستودع GitHub الخاص بالـBackend، وإضافة GitHub Actions workflow يبني APK UAT على خوادم GitHub.

## ثابت البناء

- Flutter: `3.27.3` — مطابق لـ`.metadata` في المشروع المرفوع.
- API: `https://real-estate-uat-api.onrender.com/api`
- APP_ENVIRONMENT: `uat`
- Package ID: `com.example.real_estate_mobile`
- لا توجد Supabase keys أو DB passwords أو OTP secrets داخل APK أو workflow.

## ماذا يعمل GitHub تلقائيًا؟

عند Push إلى `main` بعد إضافة هذه الحزمة:

1. يتحقق من بصمات ملفات Cloud Readiness المقبولة.
2. يشغل `flutter pub get`.
3. يشغل `flutter analyze`.
4. يشغل اختبار Cloud Readiness ثم كل Flutter tests.
5. يشغل اختبارًا إضافيًا يثبت أن build-time config هو UAT والرابط HTTPS الصحيح.
6. يفحص `/api/health` على Render ويتطلب `database=true` و`postgis=true`.
7. يبني Release APK باستخدام نفس dart-defines.
8. يرفع Artifact باسم `real-estate-uat-apk-<run>` ومعه SHA-256 وBUILD_INFO.

## طريقة الإضافة

محتويات هذه ZIP مصممة لكي تنسخ إلى **جذر** المستودع المحلي الحالي:

`D:\GitHub\real-estate-uat-backend`

بعد النسخ سيكون عندك في الجذر:

- `.github\workflows\build-uat-apk.yml`
- `mobile_app\...`
- وبقية ملفات Backend الموجودة أصلًا.

بعد Commit + Push من GitHub Desktop يبدأ البناء تلقائيًا.

## ما تم استبعاده من المصدر المرفوع

- `build/`
- `.dart_tool/`
- `.idea/`
- `.flutter-plugins*`
- `android/local.properties`
- ملفات النسخ القديمة `*.stage1_before_usb_fix` و`*.stage3.bak`
- أي APK محلي سابق

