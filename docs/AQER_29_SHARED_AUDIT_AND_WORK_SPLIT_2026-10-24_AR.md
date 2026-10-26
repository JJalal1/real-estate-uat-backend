# عقار — تدقيق أولي وتوزيع عمل البنود الـ29 (24 أكتوبر 2026)

> **ليس شهادة إغلاق**: تدقيق مصدر GitHub وCI وتقارير UAT واتصالات Supabase. لا تتوفر المواصفتان الأصليتان للمطابقة الحرفية (جرى البحث في Drive وملفات المحادثة). حالات القبول على هاتف حقيقي/حسابات مفعلة أو مزودي Production ظلت منفصلة.

## نطاق ومصدر
- UAT branch: `work/wave2-review-current`, آخر SHA مؤكد `e7aad95bd744be0527d4594590d02e58f4e41b7a` عند بدء التدقيق.
- العمل على النسخة الحالية المستهدفة للإطلاق، لا نسخة APK1123 التاريخية.
- استبعاد مؤقت: #3 و#21 الفيديو بسبب التكلفة، و**تفعيل وهجرة** #11 بسبب عدم إثبات backup/restore. لا إسقاط دائم لأي منها.
- #20 داخل 29 لكن OFF/مشروط.
- #109 أداء الخادم **بوابة إطلاق مستقلة** وليست أحد الـ29.
- المرجع: `docs/APPROVED_32_RELEASE_MATRIX_AR.md` وتقارير #11/#12 و#13/#16 وقرارات التأجيل.
- PR #122 `work/performance-109-uat-journeys` (رأس `c9d5ab454cde0b9db0b8695f7eaab803a375f161`) Draft/غير مدموج ولا يُعاد شغله هنا.

## مصفوفة توزيع أولي
| # | الوظيفة | حالة الدليل الحالية | المسؤول والخطوة التالية |
|---:|---|---|---|
| 1 | ملاءمة صور الإعلان | UAT code | عمل مشترك: CI مراجعة كل صورة مثبت؛ Work يكمل رحلة موظف/صاحب إعلان حي |
| 2 | تحسين صور الإعلان | UAT code | أنا: تدقيق مشتقات JPEG/EXIF/الترتيب؛ هاتف لاحقًا |
| 4 | العلامة المائية | UAT live | أنا: رصد مشتقات v2 وتنظيفها؛ قبول بصري على هاتف |
| 5 | مشاركة العقار | code; Android gap identified | أنا: تصحيح intent filters في هذا PR واختبار Flutter؛ Android sharing chooser حقيقي لاحقًا |
| 6 | منع التكرار | CI blocker | Work: إكمال PR122 وكشف سبب duplicate_same_physical_asset؛ لا تخفيف assertions |
| 7 | البلاغات | existing code | Work: حالات البلاغات والأدوار على حسابات UAT اصطناعية مع إثبات مسار |
| 8 | الإشعارات | disabled-by-default UAT | أنا: تدقيق عدم تسريب token وتكوين؛ FCM وqueue/Production لاحقًا |
| 9 | البحث العربي | CI and limited UAT | أنا: تنظيم fixtures؛ Work: حالات أدوار/لهجات وتعديل إن لزم |
| 10 | حظر المستخدمين | code and PG tests | Work: تجاوز الحظر وحالات الطرفين من HTTP فعلي |
| 12 | جودة الصور المتكيفة | UAT live measured | أنا: حماية regressions؛ قبول Android Metered/DataSaver لاحقًا |
| 13 | Lazy loading/viewport | UAT measured | أنا: تثبيت قياس 21→2؛ هاتف حقيقي لاحقًا |
| 14 | التخزين المؤقت | CI partial | أنا: متابعة TTL/invalidation/account leaks؛ قياس p95 مقترن #109 |
| 15 | حماية ضعف الشبكة | CI flows | أنا: سيناريوهات retry؛ اختبار مودم Android مجمع |
| 16 | Skeleton/loading/error | CI key flows | أنا: المراجعة؛ الهاتف/الأدوار لا زالت بوابة |
| 17 | تجميع الخريطة | Dart tests | أنا: اختبار خوارزمية/selected; قبول zoom/drag هاتف لاحقًا |
| 18 | Pagination | loopback + UAT | أنا: coverage صفحات؛ Work: تحقق صفحات محمية ببيانات UAT تجريبية |
| 19 | Debounce/stale responses | Flutter tests | أنا: تثبيت cancellation regression؛ جهاز مجمع |
| 20 | Prefetch | OFF intentional | لا تشغيل دون مقارنة قبل/بعد تثبت تحسنًا دون كلفة بيانات غير آمنة |
| 22 | Deep Links/App Links | code; production gated | أنا: Android custom intent paths في PR مستقل؛ Work/إطلاق: HTTPS assetlinks/دومين وشهادة حقيقية لاحقًا |
| 23 | شوهد مؤخرًا | CI actor-isolated | أنا: خصوصية حساب/زائر وIO regression؛ قبول هاتف لاحقًا |
| 24 | حفظ حالة الاستكشاف | HTTP measured | أنا: رصد العودة دون تنزيل إضافي؛ هاتف لاحقًا |
| 25 | لا نتائج | CI+UAT sample | أنا: حالات فراغ مقابل خطأ؛ هاتف لاحقًا |
| 26 | بوابة التحديث | code; production gated | أنا: تدقيق fail-open ونسخ build؛ Store URL/identity لاحقًا |
| 27 | الصلاحيات عند الحاجة | partial older handset | أنا: مسح طلب الموقع/الميكروفون/الإشعارات؛ Work إن ظهر عطل native أصعب |
| 28 | إزالة EXIF/GPS | live synthetic evidence | أنا: اختبار عينات حقيقية مصطنعة؛ نتائج الهاتف لاحقًا |
| 29 | إدارة صور الإعلان | CI and code | Work: UAT owner/editor/replace/delete/idempotency؛ أنا: فحص source/CI |
| 30 | المسودات | CI and PG code | Work: انقطاع/حسابين/استعادة عبر HTTP؛ أنا: الاختبارات الموجهة |
| 31 | حذف الحساب | service+tests | Work: مستخدم اصطناعي مخصص وتنظيف قانوني/Storage؛ لا بيانات أشخاص |
| 32 | الثيم | Flutter tests | أنا: ثيم وRTL وتكبير نص؛ هاتف كامل لاحقًا |

## أول فجوة مستقلة اكتشفناها وأصلحناها في هذا الفرع
- `mobile_app/android/app/src/main/AndroidManifest.xml`: كان يستقبل custom deep links `/properties` فقط رغم أن Flutter ينشئ ويفسّر `/advertisers`, `/messages`, `/bookings`, `/agreements`, `/rental-contracts`, `/broker/deals`. أضفنا intent-path declarations لجميع هذه المسارات.
- اختبار مصدر Android في `mobile_app/test/phase5_deep_links_test.dart` يراجع وجود المسارات؛ لا يثبت OS intent dispatch أو الصلاحيات. يلزم CI/Android handset قبل دمج PR.
- حاليًا HTTPS App Links تخص مسار العقارات فقط، وتتطلب لاحقًا دومين وassetlinks وشهادة توقيع معتمدة. لا تخلطها مع custom scheme.

## مراجعة فشل PR122 (Work — لا نعدل فرعه بالتوازي)
- على `c9d5ab4` نجح test backend SQLite بينما فشل test postgres `Measured backend contracts (pgsql)` عند `uat:role-journeys`: حالتا `duplicate_same_physical_asset` و`execution_exception`؛ الحالات السابقة تضمنت استعادة مسودة وحماية الصور ومراجعة صور إيجابية/سلبية.
- Work يعزل السبب الحقيقي في duplicate identity والتحقق منه/إصلاحه مع الحفاظ على قواعد المنتج، ثم يكمل حالات البلاغات والحظر وحذف الحساب دون تجاوز أمان وحظر بيانات حقيقية. لا ندمج PR122 قبل نجاح جميع الحواجز.
- probe UAT read-only أثبت p95 warm health≈635ms, thumbnail≈1826ms, marketplace≈1919ms (20 طلبًا لكل مسار، التزامن ≤3)؛ لا يثبت معالجة الاستيقاظ cold-start ≈34.9s أو حمل Production؛ issue #109 مفتوحة.

## مراجعة أمان Supabase (قراءة فقط)
- النسخة UAT ما زالت 59 migrations وجدول `listing_image_upload_intents` غير موجود؛ bucket الخاص غير عام.
- Supabase advisors يعرضون 88 تنبيه INFO لنمط RLS بلا policies في جداول Laravel، و162 INFO لمؤشرات لم تُستخدم حتى الآن؛ **لا تفتح GRANT/policies، ولا تحذف indexes آليًا**. التحقق من اتصال Laravel وصلاحيات الخدمات لا يحوله إلى تسرب مباشر.

## طريقة تعاوننا
1. **أنا هنا:** جرد المصدر، فحص CI/Render/Supabase، اختبارات منع التراجع، إصلاحات منخفضة المخاطر مع PR مستقل، توثيق أدلة وتدقيق تقارير Work.
2. **Work:** إصلاحات أمن/تزامن/صلاحيات أصعب، HTTP UAT بحسابات اصطناعية وبراهين، قياسات أداء ذات أسبقية، تشخيص أعطال CI وإصلاحها في الفرع الخاص به.
3. لا نعمل على نفس الملف أو branch بالتوازي، ولا ندمج قبل CI والتأكد من مطابقة source SHA والنشر، ونحافظ على الغموض حول المواصفات المفقودة بدل الاختراع.
4. لا Production ولا موارد مدفوعة ولا تفعيل #11/الفيديو ولا قبول هاتف فردي دون قرار مالك؛ APK UAT موحد لاحقًا.
