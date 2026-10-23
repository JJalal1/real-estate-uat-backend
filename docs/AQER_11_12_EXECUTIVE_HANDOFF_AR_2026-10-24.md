# عقار — تسليم تنفيذي للبندين #11 و#12 — 24 أكتوبر 2026

هذه متابعة على النسخة الحالية المستهدفة للإطلاق وفرع `work/wave2-review-current`. **#11 غير مكتمل وغير مفعّل؛ #12 منفذ ومنشور ومثبت آليًا على UAT، مع بقاء قبول الهاتف المجمع واختبارات الشبكة الأصلية على الجهاز.** لا تغييرات Production ولا موارد مدفوعة ولا APK قبول منفصل.

## ما استلمناه وما تغير فعليًا

عند الاستلام كان UAT عند `d6b14935a5e865f448c931c8ff5a432c9cb1f04b` بعد دمج #117. PR #115 و#118 كانا Draft، واختبار TUS السابق فشل عند الإنشاء. راجعنا GitHub وRender وSupabase قبل التعديل؛ أكدت CI نجاح Flutter النهائي أيضًا على رأس #118 `0640fa837dc403897fdb53a59187871859061a36`.

- دُمج #118 بعد نجاح فحوصه، وصُحح التوقيع والمسار، ثم نجح اختبار TUS فعلي بملف اصطناعي فقط.
- عولج تعارض #115، وأضيفت معالجة فقدان رد الإنهاء، تجديد التوقيع، قفل تنظيف المخلفات، وحماية روابط الجلسات والمفتاح العام، ثم دُمج مصدر #12 في الفرع المعزول دون دمجه في UAT.
- أضيف #12 في PR #119: مشتقات أصغر، اختيار URL فعلي بحسب السياق والشاشة وكلفة الاتصال ونقل مقاس، تكبير صريح، وكاش جلسة محدود وإلغاء الطلبات.
- فحص التراجع الكامل كشف ثلاث fixtures قديمة تتجاوز مراجعة كل صورة قبل النشر. صُححت باستخدام API مراجعة الموظف الموجود، مع إبقاء قيود المنتج وتأكيدات الاختبارات.
- أُضيف تشغيل Broker Experience CI الأصلي على PR المستهدف إلى UAT، حتى تظهر بواباته قبل الدمج.

## #11: ما ثبت وما لم يثبت

تنفيذ Supabase الموقّع يستخدم `/storage/v1/upload/resumable/sign` مع `apikey` عام و`x-signature` خاص بالمسار، وTUS 1.0.0 وحزم 6 MiB. المفتاح الخدمي لا يصل إلى Flutter، وطلبات Aqer إلى Laravel مستقلة عن تصريح Storage. مراجع المراجعة: [Supabase resumable uploads](https://supabase.com/docs/guides/storage/uploads/resumable-uploads) و[المثال الرسمي الموقّع](https://github.com/supabase/supabase/tree/master/examples/storage/resumable-upload-signed-uppy).

الاختبار الحي على Render مرتين استعمل ملفًا اصطناعيًا حجمه **6,291,502 بايت**. أرسل أول PATCH **6,291,456** بايت، توقف بين الحزمتين، ثم HEAD أثبت offset المطابق، ثم أرسل PATCH من **46** بايت فقط. تحققت الأداة من الحجم وSHA-256 بعد التنزيل وحذفت الكائن في النهاية. رفضت أيضًا توقيعًا مصطنعًا. سجلات Supabase المستقلة للأولى أثبتت POST 201 وPATCH 204 بالحجمين المذكورين وHEAD 200 وPOST 400 للتوقيع الخاطئ. الاختبار توقف بين الحزم؛ لم يحاكِ فصل راديو هاتف أثناء إرسال حزمة.

الدليل: [سجل البروتوكول](evidence/2026-10-24-tus-live-wire.json)، ومسار الأداة `uat:signed-tus-storage-probe`. سجلات الموفر لا تحتفظ بقيمة Upload-Offset؛ التحقق الدقيق منها داخل الأداة شرط نجاح. فحص `storage.objects` بعد التنفيذ: صفر كائنات مكتملة تحت `private/uat-health/tus-%`. لا يعني ذلك استعلامًا عن كل جلسة TUS غير مكتملة في المزود.

أهم الإصلاحات على PR #115:
- الاحتفاظ بملف جلسة TUS المكتملة حتى يؤكد Laravel الإنهاء، كيلا يُنشأ POST جديد عند فقدان رد finalize؛ اختباره يعيد HEAD بلا إعادة بايتات.
- مهلات نقل محدودة، إغلاق النقل، ورفض Location خارج origin أو يحوي userInfo/query/fragment.
- رفض JWT بدور service_role عند موضع المفتاح العام.
- تجديد التوقيع لنفس SHA/الحجم/MIME في محاولة pending فقط، وتمديد مهلة التنظيف من آخر إصدار مع هامش **27 ساعة**.
- تنظيف صفوف المحاولات داخل transaction وlockForUpdate مع إعادة فحص الحالة والمهلة، وحفظ tombstone للإلغاء والحذف.
- فحص PostgreSQL حقيقي على قاعدة مؤقتة يثبت RLS والمنع المباشر على الجدول وتسلسله للأدوار anon/authenticated.

**المانع الفعلي:** لم نحصل على dump كامل مشفر لقاعدة UAT ولم ننفذ استعادته في PostgreSQL مستقل. أدوات الاتصال الحالية توفر SQL ولا توفر تنزيل نسخة كاملة أو قناة آمنة لسر قاعدة البيانات؛ بيئة التنفيذ المحلية لا تحتوي PostgreSQL/Docker؛ PostgreSQL المؤقت في CI متاح للاختبار لكن ليس لديه قناة نسخة UAT أو بيانات اتصالها السرية، ولا أُنشئت بيئة مدفوعة بديلة. مستند SQL أو بصمات الجداول أو نجاح migrations في CI ليست نسخة احتياطية. [إجراء الاستعادة](IMAGE_TUS_UAT_BACKUP_RESTORE_AND_CANARY_GATE_AR.md) يظل إجراءً غير منفذ.

لذلك لم تُطبق هجرة `2026_10_23_220000_create_listing_image_upload_intents.php`، ولم يُدمج PR #115 أو ينشر. لا يزال جدول المحاولات غائبًا، و`LISTING_IMAGE_RESUMABLE_ENABLED=false` و`UAT_RUN_MIGRATIONS=false` و`UAT_IMAGE_TUS_PROBE_ON_STARTUP=false`. علم Flutter الجديد افتراضيًا OFF. دورة Flutter ← Laravel intents ← Supabase كاملة، وتجربة إعادة فتح التطبيق وتبديل حسابين وانتهاء التوقيع والحذف وجدولة التنظيف على UAT، **باقية**؛ اختبارات CI لهذه الحالات لا تعوض تشغيلها الحي.

## #12: التنفيذ والقياس

Laravel ينتج JPEG من أصل خاص، دون upscale: thumb 320/q64، card 640/q80، preview 960/q72، detail 1280/q85، gallery 1920/q88، zoom 3072/q92. المشتق الناقص لإعلان قديم يولد عند الطلب وحده. لا تحويل Supabase مدفوع. الوصول يُفحص قبل 304؛ الصور الخاصة no-store ولا ETag عام.

Flutter يختار الملف المطلوب فعلًا حسب مساحة العرض وDPR وAndroid metered وData Saver. اتصال Wi-Fi لا يفترض سرعة أو إعفاء من الكلفة. قياسات النقل الفعلي في المقدمة تؤثر لمدة 60 ثانية للشبكة نفسها، دون تنزيل speed test. المجهول/المحدود/البطيء: بطاقات thumb وتفاصيل card. التكبير العالي يُطلب بإجراء صريح مع الاحتفاظ بالصورة السابقة حتى يصل.

الكاش ذاكرة جلسة فقط، بحد خمول 18 صورة/24MiB/دقيقتين؛ الطلب مشترك ويُلغى عند مغادرة آخر عارض. تبديل الحساب يمحو الكاش ويلغي النقل ويُخلي الصور المفكوكة، والرد القديم لا يعيد بياناته إلى الجلسة الجديدة. واجهات التفاصيل والمعرض والمصغرات تعرض حالات التحميل/الخطأ وإعادة المحاولة.

القياس قبل النشر كان على API `23ddba16…`، وبعده على `6a0475e8…`. استخدمنا **ثلاثة مراجع fixtures منشورة اصطناعية 60–62؛ قد تشترك في أصل صورة**، لا عينة سوق عامة. الأرقام حجم payload دون ترويسات/TLS، وأزمنة الجدار تشمل API وStorage. راجعنا المصدر السابق: صورة رأس التفاصيل كانت تطلب gallery صراحة، والبطاقات card؛ المقارنة تقابل الطلب السابق والاختيار الجديد، وليست تغيير cacheWidth فقط.

| المسار على المراجع الثلاثة | قبل اختيار الملف | بعد الاختيار | التوفير |
|---|---:|---:|---:|
| تفاصيل على اتصال مقيّد: gallery → card | 765,344 B | 194,483 B | **74.59%** |
| بطاقات على اتصال مقيّد: card → thumb | 194,483 B | 39,743 B | **79.56%** |
| إعادة تحقق thumb مع ETag | تنزيل الجسم | 304 / صفر B | ثلاث استجابات مثبتة |

| مرجع fixture | gallery: B / ms بعد النشر | card: B / ms بعد النشر | thumb: B / ms لأول طلب |
|---|---:|---:|---:|
| 60 | 191,512 / 1,317 | 51,649 / 971 | 11,337 / 2,806 |
| 61 | 286,916 / 1,744 | 71,417 / 1,566 | 14,203 / 1,898 |
| 62 | 286,916 / 1,355 | 71,417 / 1,178 | 14,203 / 2,365 |

في قراءة مضبوطة **64KiB/s** للمرجع الأول قبل النشر: gallery **4,066ms** وcard **1,720ms**؛ بعد النشر: gallery **3,941ms** وthumb **998ms**. هذه آلية إبطاء القارئ، وليست محاكي شبكة Android أو قياس p95. لا نستنتج من عينات مفردة تحسن latency العام؛ كلفة توليد thumb لأول مرة ظاهرة في الجدول.

اختبار Flutter الحي بعد النشر قرأ Laravel الذي يجلب من Storage الخاص، واختار card للتفاصيل المقيدة: **191,512 → 51,649 B**، طلب واحد لعارضين متزامنين، و**صفر بايت إضافي عند العودة**. قياس Python أعاد `adaptive_available=true` وthumb HTTP200 و304، بخلاف baseline الذي أعاد thumb422.

الأدلة الدائمة: [قبل](evidence/2026-10-24-images-before.json)، [بعد](evidence/2026-10-24-images-after.json)، [Artifact القياس](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40032116209/artifacts/12536287735). SHA256 لأرشيف artifact: `5492013183acb5ec7a80d033f3065f54eeb7117da9aed4e5ec6abd5fd4468b2c`.

## GitHub ومصدر UAT

| PR | الحالة | المصدر/الدمج |
|---|---|---|
| [#115](https://github.com/JJalal1/real-estate-uat-backend/pull/115) | Draft، معزول، قابل للدمج عند الفحص؛ بوابة backup باقية | رأس الكود المصحح `3f89182521910bfd910a960bb5a4f2a55a919be3`؛ ليس SHA نشر |
| [#116](https://github.com/JJalal1/real-estate-uat-backend/pull/116) | أُعيد استخدام PR الوثائق الموجود لهذا التسليم، دون إنشاء PR إضافي | ملفه الأصلي كان إجراءً غير منفذ وDraft عند فحصنا؛ حالة دمجه النهائية في سجل PR |
| [#117](https://github.com/JJalal1/real-estate-uat-backend/pull/117) | مدموج قبل الاستلام | `d6b14935a5e865f448c931c8ff5a432c9cb1f04b` |
| [#118](https://github.com/JJalal1/real-estate-uat-backend/pull/118) | دُمج في هذه المتابعة | `23ddba16d33e50b45a954d9d5e0d2dfe67737d8a` |
| [#119](https://github.com/JJalal1/real-estate-uat-backend/pull/119) | دُمج في هذه المتابعة | `6a0475e82b3a12f59cab3eb78ba75ee4e283186b` |

مصدر #12 المختبر `ef4d16e7fca6b5e42fd72b9fa9bd475b540adca7` وشجرة `ce128dc6ae3ae08548e68db4f9b03eaf0116668b`؛ شجرة دمج #119 مطابقة تمامًا. هذا SHA الكود المنشور. أي دمج لاحق لهذا التقرير فقط لا يغيّر شجرتي backend/mobile ولا يُمثَّل كنشر جديد. SHA دمج #116 النهائي يؤخذ من GitHub ويُذكر في رسالة التسليم؛ لا يمكن تثبيت SHA commit داخل محتواه نفسه.

## نتائج CI

المجاميع المتداخلة لا تُجمع كاختبارات فريدة. النتائج التالية تخص المصدر المختبر #12 المذكور أعلاه:

| Workflow / Run | النتيجة المثبتة |
|---|---|
| [Broker Experience CI / 40032116352](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40032116352) | البوابات الخمس نجحت: checkpoint، Laravel، PostgreSQL، Docker، Flutter/native؛ fallback المشفر skipped لعدم الحاجة |
| Laravel original regression | **352 passed، 1 skipped، 4,323 assertions**؛ تخطي PostGIS في SQLite مغطى في PG الحقيقي |
| Disposable PostgreSQL17/PostGIS | **175 tests / 2,775 assertions** في ثماني مجموعات |
| Flutter original regression | **357 selected** و**498 full passed، 1 skipped**؛ اختبار UAT الحي opt-in نُفذ منفصلًا؛ فحص بيئة compiled UAT واحد ناجح؛ build/native تحقق ناجح |
| [Adaptive Image Quality / 40032116209](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40032116209) | 3 jobs ناجحة: strict analyze بلا diagnostics، **47 Flutter**، **14 Laravel / 249 assertions**، وقياس UAT + **1 live Flutter**؛ أُعيد job الحي بعد النشر في attempt2 / job120690776224 |
| [Launch Readiness Wave4 / 40032116230](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40032116230) | Laravel وFlutter/native ناجحان |
| [Release Integrity PostgreSQL / 40032116220](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40032116220) | ناجح |

PR #118 اجتاز workflows الأربعة وخمسة jobs على `0640fa83…` قبل الدمج. PR #115 على `2770c867…` اجتاز workflows الخمسة؛ مخصص TUS **2 Flutter** و**16 PHP /179 assertions**، وPG integrity **2 tests /31 assertions**. بعد توحيد #12 كشف run40034798057 نقص فهرس FK user_id في الهجرة المعزولة؛ فشل PostgreSQL وأصبح Flutter اللاحق skipped، رغم نجاح بقية الاختبارات. أضيف الفهرس في `3f89182521910bfd910a960bb5a4f2a55a919be3` دون تغيير اختبار التدقيق. نتائج الرأس المصحح موثقة في ملحق التحقق أدناه، ولا تُنسب نتائج رأس قديم تلقائيًا إليه.

الفشل الذي ظهر أثناء التنفيذ: diagnostics تنسيق Flutter حقيقية عولجت؛ ثلاث fixtures نشر قديمة عولجت دون تخفيف المراجعة؛ EOF زائد في دمج #115 صحح. لم نخفف قواعد lint أو نلغِ اختبارًا فاشلًا. فشل TUS السابق `dep-dbdsitom7kps73bigba0` يعود إلى ما قبل الاستلام، واحتُفظ به كتاريخ في #116.

## نشر Render وSupabase

الخدمة `real-estate-uat-api-frankfurt` / `srv-dahj3vlg1s2s73bdqhtg` ضمن `tea-d4v0q98gjchc73cistt0`، Free، auto-deploy OFF، فرع UAT المعتمد.

| Deploy | SHA | الحالة / نهاية UTC |
|---|---|---|
| dep-dbdtcp5g1s2s73b18o80 | 23ddba16… | Live / 2026-10-23 21:50:20؛ TUS pass 21:50:10 |
| dep-dbdtcrebv0ns73br2ps0 | 23ddba16… | Live / 21:51:18؛ TUS pass 21:51:08 |
| dep-dbdtdcec36kc73813fdg | 23ddba16… | Live / 21:52:00؛ startup probe OFF |
| dep-dbdttugae00c73b0087g | 6a0475e8… | **Live / 22:27:03**؛ #12، health200 ثم قياس UAT ناجح |

تحديث env في Render أطلق نشرًا رغم auto-deploy OFF؛ ثم أطلقنا يدويًا نشر canary ثانيًا زائدًا، لذا شُغّل الاختبار مرتين. كلاهما اصطناعي ونجح ونُظف. إعادة العلم إلى OFF أطلقت نشر الاستقرار الثالث. نشر #12 أُطلق مرة واحدة. لا يُخفى النشر الزائد، ولا اعتُبر شرطًا للميزة.

على Supabase لم نطبق migration أو RLS/GRANT أو تغيير bucket/policy. بقيت **59 migrations**، bucket خاص، كل جداول public عليها RLS، وصفر policies Storage. بصمات/أعداد **15 جدولًا ماليًا** قبل #12 وبعده متطابقة، دون حفظ بيانات مستخدمين أو hashes صفوفهم في المستودع. هذه مقارنة سلامة وليست backup. كتابات Storage اقتصرت على canary المحذوف ومشتقات مطلوبة وhealth probes القائمة. سجلات Render error خالية في نافذة 22:26–22:34 UTC؛ هذا نطاق رصد محدد وليس ضمان انعدام كل خطأ.

[دليل السلامة المنقّح](evidence/2026-10-24-uat-safety.json).

## المتبقي وخطوة الاستلام التالية

1. استكمال dump مشفر حقيقي واستعادته في قاعدة مستقلة مع إثبات، ثم فقط مراجعة هجرة #11 وتطبيقها وفحص ملكية/RLS/GRANT live.
2. إكمال #11 end-to-end على UAT بحسابين تجريبيين: قطع/استعادة، فقد رد الإنهاء، إعادة فتح، انتهاء توقيع، حذف، إلغاء، وتنظيف scheduler. نجاح canary هو إثبات بروتوكول جزئي.
3. قبول #12 على Android حقيقي مع Data Saver وشبكة بطيئة وتنقل سريع وكبير الشاشة والعودة وتبديل حساب؛ لم تُسلّم APK منفصلة. لا نزعم اختبار شبكة خلوية فعلية من controlled reader أو MethodChannel mock.
4. العرض العام المنشور يحتفظ بسياسة public max-age86400 القائمة؛ تغير الإتاحة يُفحص في الخادم قبل 304، لكن عميلًا خارجيًا يملك نسخة عامة مخزنة قد يحتفظ بها حتى انتهاء TTL. الصور الخاصة no-store وكاشها داخل الجلسة.
5. اقتراح العمل التالي بعد #12: تدقيق **#13 viewport/lazy loading** وقياس الطلبات غير المرئية، مع إبقاء #11 أولوية فور توافر مسار backup/restore. #3/#21 مؤجلان مؤقتًا، وليسَا ملغيين.

## حالة البنود الـ32

الحالات غير #11/#12 من المصفوفة الموروثة؛ لم نعد قبول كل بند في هذه المتابعة. نجاح التراجع العام لا يغلقها تلقائيًا. [المصفوفة التفصيلية](APPROVED_32_RELEASE_MATRIX_AR.md).

| # | البند | الحالة |
|---|---|---|
| 1 | ملاءمة صور الإعلان | الإصلاح منشور على UAT — قبول الهاتف والتطابق النهائي معلقان |
| 2 | تحسين صور الإعلان | موجود |
| 3 | رفع الفيديو ومعالجته | مجمّد بقرار المالك — غير مغلق |
| 4 | العلامة المائية | قبول غير مكتمل |
| 5 | مشاركة العقار | قبول هاتف |
| 6 | منع التكرار | موجود؛ مراجعة تراجع |
| 7 | البلاغات | موجود؛ مراجعة تراجع |
| 8 | إشعارات الجهاز | UAT مدموج؛ Production مؤجل |
| 9 | البحث العربي | موجود؛ مراجعة تراجع |
| 10 | حظر المستخدمين | موجود؛ مراجعة تراجع |
| 11 | استئناف رفع الوسائط | غير مكتمل: TUS حي مثبت؛ backup/restore والهجرة ودورة UAT باقية، PR115 Draft |
| 12 | جودة الصور المتكيفة | منفذ ومنشور؛ قياسات UAT ناجحة؛ قبول الهاتف المجمع باقٍ، لا إغلاق قبول نهائي |
| 13 | Lazy loading / viewport | موجود؛ مراجعة تراجع |
| 14 | التخزين المؤقت | موجود؛ مراجعة تراجع |
| 15 | حماية ضعف الشبكة | قبول هاتف قديم فقط |
| 16 | Loading / Skeleton | جزئي |
| 17 | تجميع علامات الخريطة | قبول هاتف |
| 18 | Pagination | موجود؛ مراجعة تراجع |
| 19 | Debounce ومنع النتائج القديمة | موجود؛ مراجعة تراجع |
| 20 | Prefetch محدود | مشروط؛ غير مفعل عمدًا |
| 21 | تشغيل الفيديو عند الطلب | مجمّد بقرار المالك — غير مغلق |
| 22 | Deep Links / App Links | UAT موجود؛ Production مؤجل |
| 23 | شوهد مؤخرًا | قبول هاتف |
| 24 | الحفاظ على حالة الاستكشاف | موجود؛ مراجعة تراجع |
| 25 | نتائج البحث الصفرية | موجود؛ مراجعة تراجع |
| 26 | بوابة التحديث | UAT موجود؛ Production مؤجل |
| 27 | طلب الصلاحيات وقت الحاجة | قبول هاتف قديم فقط |
| 28 | خصوصية metadata للصور | موجود؛ مراجعة تراجع |
| 29 | إدارة صور الإعلان | قبول هاتف قديم فقط |
| 30 | المسودات وحماية الخروج | قبول هاتف قديم فقط |
| 31 | حذف الحساب الحقيقي | UAT موجود؛ قبول هاتف لاحقًا |
| 32 | المظهر فاتح/داكن/النظام | قبول هاتف |
## ملحق التحقق من فرع #11 بعد توحيد #12

الرأس المصحح: `3f89182521910bfd910a960bb5a4f2a55a919be3`، شجرة `9c6ba0d5ed6126a47768df90b7430411044217e2`. لم يدمج في UAT.

- [Broker Experience CI /40035235366](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235366): **ناجح بالكامل**؛ البوابات الخمس checkpoint وDocker وLaravel وPostgreSQL وFlutter/native ناجحة، وfallback المشفر skipped لعدم الحاجة.
- Laravel الكامل: **362 passed /4,387 assertions** وskip واحد لـPostGIS على SQLite.
- PostgreSQL17/PostGIS: **181 tests /2,832 assertions** في ثماني مجموعات، مع فهرس FK وRLS ناجحين.
- Flutter: **357 selected** و**500 full passed /1 skipped** لاختبار UAT opt-in الذي نجح منفصلًا في workflow التكيف؛ compiled UAT endpoint وبناء APK والتحقق Native والتشفير ناجحة. بناء CI ليس APK قبول منفصلة مسلّمة للمالك.
- [Listing Media Resume Stage1 /40035235290](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235290)، [Adaptive Image Quality /40035235296](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235296)، [Release Integrity PG /40035235373](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235373)، [Signed TUS contract /40035235295](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235295)، [Private Storage Preflight /40035235317](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235317): جميعها ناجحة.
- [Launch Readiness Wave4 /40035235323](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40035235323): Laravel وFlutter والتحليل وبناء Android جميعها ناجحة. **workflows السبعة ناجحة على الرأس نفسه**. تشغيل فحص التخزين الموروث لا يعني تنفيذ الفيديو المؤجل.
