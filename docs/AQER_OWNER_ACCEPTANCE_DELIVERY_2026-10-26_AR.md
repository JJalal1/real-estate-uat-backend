# عقار اليمن — تقرير تسليم القبول الهندسي ٢٦ أكتوبر ٢٠٢٦

هذه وثيقة حالة تنفيذية وليست شهادة اعتماد متجر. تم إنجاز تجهيز الدفعة المستقلة ودمج إصلاحاتها وفحص UAT وAndroid emulator، وبقي قبول المالك والخدمات والاعتمادات المبينة. لا هاتف فعلي اختُبر في هذه المهمة.

**الحالة: ٤ مكتملة ومعتمدة، ٢٠ جاهزة وتنتظر اختبار المالك، ٤ لها مانع خارجي محدد، ١ OFF معتمد مشروط. المتاجر وProduction: NO-GO.**

المصفوفة الحالية هي أساس المواصفة. ملفا `AQER_Prioritized_Development_Plan_AR.pdf` و`REAL_ESTATE_APPROVED_ENHANCEMENTS_32_AR_RTL.docx` لم يوجدا في المصادر المتاحة؛ لا ندعي المطابقة الحرفية لهما. العمل على المشروع نفسه وبنفس المعمارية؛ لا مشروع بديل.

## المصدر والبناء والدليل

- دمج الشيفرة المعتمد: `44a5429d91827f2da73938b71c877c38572dd663`؛ شجرته `3af2e39466e203bdd7314ab5d095100f2d49271a`.
- رأس PR158 المختبر: `c72e8aa4560502d5c992433837046a4e21438731`؛ مصدر APK الموثق: `4365a9ad4000a42a72bcfad2693e230e9b9d70af`. شجرة commit الدمج الافتراضي في Actions متطابقة مع شجرة الدمج الفعلي؛ لا نخلط SHAs أو ننسب نجاح رأس قديم لرأس جديد.
- [تشغيل CI للحزمة النهائية](https://github.com/JJalal1/real-estate-uat-backend/actions/runs/40324345556)؛ `19` فحصًا ناجحًا، و`1` فحص transport اختياري متخطى دون تجاوز فحص فاشل.
- Laravel الأصلي: **423 نجاحًا / 4987 assertions**؛ تخطٍ قائم واحد لاختبار PostGIS في SQLite. محرك PostgreSQL17/PostGIS له Job مستقل ناجح؛ لا skip جديد لإخفاء عطل.
- Flutter المركزة: **156/156 نجاحًا، 0 skip**؛ artifact `12650716142` للرأس الحالي. إجماليها70 حالة بيانات ل35 شاشة،71 حالة خصوصية/تخطيط ثانوية،15 بوابة حساب/نوافذ. الاختبارات الكاملة وفحص البناء ضمن التشغيل النهائي.
- Flutter الكامل: **791 نجاحًا و6 اختبارات HTTP اختيارية معطلة في الجولة العامة**؛ الستة شُغلت ونجحت منفصلة على الرأس نفسه:5 في viewport/discovery و1 adaptive_image_uat، بأعلام التفعيل الصريحة. لا تخطٍ لاختبار فاشل.
- UAT V5: **170 تحققًا / 118 HTTP / cleanup=true** على الخادم وقاعدة/Storage UAT، ثم preflight مالك مستقل بالنتيجة أدناه.
- owner preflight `2026-10-26-owner-v2`: **passed**؛ `52` إيصالًا؛ سُحبت جلسات الفحص فقط. لا يعاد تشغيله عند النشر العادي.
- لم تُوسع GRANT أو تجعل الملفات عامة، ولم تنفذ DDL جديدًا أو هجرة11 أو خدمة مدفوعة أو Production أو نشر متجر. Prefetch والفيديو وTUS تبقى وفق بواباتها.

V5 نُفذت عند `89151ade9b128091b5faa45d104218be4deac8c7`. شجرات Http/Services/Models/routes/database مطابقة للدمج الحالي، كما في `2026-10-26-api-component-equivalence.json`. لم نكرر V5 على SHA جديد أو ننسب تاريخها إليه؛ فحص preflight المالك52 تحققًا نُفذ فعلًا على44a5429d الحالي.

## مصفوفة البنود٢٩

الحالة الجديدة لا ترفع بندًا ذا خدمة أو اعتماد باقٍ إلى «جاهز للمالك». «مكتمل ومعتمد» للحكم الخاص بالبند ضمن نطاقه، و«جاهز» لا يعني أن تجربة الهاتف نفذت.

| # والبند | المطلوب | قبل الدفعة | ما راجع/أصلح الآن | اختبارات وتكامل | ملفات وPRs | Android | الحكم الجديد | المانع |
|---|---|---|---|---|---|---|---|---|
| 1 — ملاءمة صور العقار ومراجعتها | لا يُنشر الإعلان قبل مراجعة بشرية لكل صوره الحالية، مع ربط القرار ببصمة تمنع استخدام موافقة لصورة استُبدلت. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. إصلاح صفحة تحقيق الإعلان الداخلية وربطها بالحساب، وحجب الأدلة/الطلبات المتأخرة بعد الخروج والدخول بالحساب نفسه، وإصلاح تجاوز العنوان للشاشة. | رحلات UAT للمراجعة وبصمة الصورة ورفض الوصول؛ preflight الجديد يثبت أن المراجع يستطيع فتح إعلان القبول الحالي وصورتيه. اختبار الشاشة الداخلية وإبطال الأدلة المتأخرة ضمن PR158. HTTP→Laravel→PostgreSQL→Storage؛ يمنع النشر قبل مراجعة الصورة الحالية. | [backend-api-runtime/app/Http/Controllers/Api/ListingReviewController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/ListingReviewController.php)<br>[mobile_app/lib/features/reviews/presentation/listing_review_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/reviews/presentation/listing_review_screen.dart)<br>[#114](https://github.com/JJalal1/real-estate-uat-backend/pull/114) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#143](https://github.com/JJalal1/real-estate-uat-backend/pull/143) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 2 — تحسين الصور والضغط والمشتقات | أصل خاص ومشتقات عرض JPEG مضبوطة الحجم والجودة، مع رفض الملفات غير الصالحة وعدم تكرار النقل بلا حاجة. | يحتاج تجهيزًا إضافيًا | إثبات OOM عند3 عمليات24MP داخل512MiB ثم قفل قبول غير حاجب503 قبلGD؛ نجاح العمليات الست؛ إصلاح مشاركة inode بينCLI وweb. | قياس Docker حقيقي: 24MP و512MiB و1CPU؛ فشل OOM baseline عند التزامن3، ثم 6/6 عمليات ناجحة بالتزامن1/2/3 دون OOM مع backpressure503. أقصى cgroup نحو357MiB؛ لا يعادل ذاكرة الهاتف. رفع/قراءة/حذف فعلي لصور اصطناعية في bucket خاص؛ قياس مشتقات عبر HTTP. | [backend-api-runtime/app/Services/ListingImageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingImageService.php)<br>[backend-api-runtime/app/Services/CloudAssetStorageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/CloudAssetStorageService.php)<br>[backend-api-runtime/app/Services/ListingImageEncodingGate.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingImageEncodingGate.php)<br>[#119](https://github.com/JJalal1/real-estate-uat-backend/pull/119) [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#150](https://github.com/JJalal1/real-estate-uat-backend/pull/150) [#155](https://github.com/JJalal1/real-estate-uat-backend/pull/155) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 4 — العلامة المائية | استخدام الأصل المعتمد وبصمته على مشتقات العرض وتنظيف مشتقات ما قبل التفعيل/التراجع دون حذف ملف مستخدم. | يحتاج تجهيزًا إضافيًا | إعادة قياس مشتقات UAT وفحص عينة العلامة بصريًا؛ مفعلة أصلًا ولم نغيّر قرارها. | مشتقات UAT v2-wm وعينة اصطناعية مفحوصة بصريًا؛ watermark_active=true ورفض الأصل422 و304. العلامة كانت ON ولم نفعلها من جديد. تنظيف الأصل ومشتقات الصورة المزالة مثبت حيًا؛ لم يُفعّل علم علامة جديد. | [backend-api-runtime/app/Services/ListingWatermarkService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingWatermarkService.php)<br>[backend-api-runtime/app/Services/ListingImageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingImageService.php)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 5 — مشاركة العقارات | مشاركة أصلية تؤدي إلى العقار الصحيح، مع رابط آمن واحترام حالة الإعلان. | يحتاج تجهيزًا إضافيًا | اختبارMethodChannel يثبت تغيّر العقار42 إلى84، وتعطيل مشاركة المسودة. | MethodChannel42→84 عند إعادة استخدام الواجهة، ومنع مشاركة المسودة؛ صفحة مشاركة UAT حقيقية للعقارات60–62. فتح التطبيقات الخارجية على الهاتف باقٍ. عقد المسار وحالة العقار محفوظان؛ فحوص Flutter وAPK. | [mobile_app/lib/core/platform/platform_share.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/platform/platform_share.dart)<br>[mobile_app/lib/router/app_deep_links.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/router/app_deep_links.dart)<br>[mobile_app/android/app/src/main/AndroidManifest.xml](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/android/app/src/main/AndroidManifest.xml)<br>[#123](https://github.com/JJalal1/real-estate-uat-backend/pull/123) [#133](https://github.com/JJalal1/real-estate-uat-backend/pull/133) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 6 — منع الإعلانات المكررة | الهوية الفيزيائية للعقار واحدة؛ إعادة الطلب أو اختلاف المعلن لا يسمحان بنشر تمثيل مكرر. | مكتمل ومعتمد | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | اختبارات HTTP حقيقية للحالة duplicate_same_physical_asset ورفض التكرار الفيزيائي؛ قيود PostgreSQL والتراجع نجحت. لم تخفف القاعدة أو assertions. HTTP حي: إعادة إنشاء بعد استجابة مفقودة 409؛ معلنان للعقار الفيزيائي نفسه؛ رفض النشر المكرر مع سبب محدد. | [backend-api-runtime/app/Services/PropertyIdentityService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/PropertyIdentityService.php)<br>[backend-api-runtime/app/Http/Controllers/Api/PropertyController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/PropertyController.php)<br>[#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مكتمل ومعتمد | لا مانع خاص بالبند ضمن نطاقه المعتمد. |
| 7 — البلاغات والإشراف | بلاغ عقار/محادثة بإيصال مستقر، queue/claim وصلاحيات للمراجعة والإغلاق؛ فتح محتوى خاص بإذن وسجل تدقيق. | مكتمل ومعتمد | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | رحلات إنشاء/تكرار/استلام/حل البلاغ ورفض القراءة الخاصة دون صلاحية وسياق بلاغ؛ اختبارات الملكية وعزل الحسابات قائمة وناجحة. HTTP حي مع PostgreSQL: إيصال/claim/resolve ورفض 403/404/409 وتدقيق الوصول الخاص؛ لا صلاحيات موسعة. | [backend-api-runtime/app/Http/Controllers/Api/SupportController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/SupportController.php)<br>[backend-api-runtime/app/Http/Controllers/Api/MessagingController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/MessagingController.php)<br>[#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#143](https://github.com/JJalal1/real-estate-uat-backend/pull/143) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مكتمل ومعتمد | لا مانع خاص بالبند ضمن نطاقه المعتمد. |
| 8 — الإشعارات | تسجيل جهاز بموافقة سليمة وتفضيلات/إلغاء، وdelivery/retry عبر مزود وqueue معتمدين، مع عزل الحساب. | يحتاج تجهيزًا إضافيًا | إعادة التحقق من الحالة والموافقة والجهاز قبل الإرسال، ومعالجةUNREGISTERED الدقيقة و429/5xx وإعادة المحاولة المحدودة ورصد قبول المزود دون ادعاء الهاتف. | 10 اختبارات دورة إرسال: إعادة فحص المستخدم/الموافقة/الجهاز، UNREGISTERED دقيق، 429/5xx وRetry-After واستنفاد المحاولات. لا FCM هاتف فعليًا؛ devices=0 عند الفحص. عقد التسجيل والتفضيلات ورفض المدخلات مثبت CI؛ إشعارات داخل التطبيق مثبتة في الرحلات. | [mobile_app/lib/features/messages/data/push_registration_repository.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/messages/data/push_registration_repository.dart)<br>[backend-api-runtime/app/Http/Controllers/Api/PushDeviceController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/PushDeviceController.php)<br>[backend-api-runtime/tests/Feature/PushDeliveryLifecycleTest.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/tests/Feature/PushDeliveryLifecycleTest.php)<br>[#132](https://github.com/JJalal1/real-estate-uat-backend/pull/132) [#139](https://github.com/JJalal1/real-estate-uat-backend/pull/139) [#151](https://github.com/JJalal1/real-estate-uat-backend/pull/151) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مانع خارجي محدد — غير جاهز للاعتماد النهائي | Firebase/FCM رسمي مطابق لهوية Android، إعداد أسراره بأمان، تشغيل عامل طابور فعلي مع queue=database، ثم إثبات وصول على هاتفين وسحب الموافقة. Push معطل الآن؛ حفظ الإشعار لا يثبت تسليمه. |
| 9 — البحث العربي | تطبيع وصلة فلاتر وترتيب وصفحات موثوق، وتمييز الصفر عن فشل الشبكة. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | بحث UAT عربي وإب/اب والفلاتر والفراغ؛ PostgreSQL17 وPostGIS؛ حمل10k اصطناعي للبحث. لا ادعاء قياس شامل لكل لهجة أو خدمة صوت خارجية. بحث HTTP/PG وfixture اصطناعي دقيق؛ عينة أداء محددة لا شهادة شاملة لكل لهجة أو مزود AI. | [backend-api-runtime/app/Http/Controllers/Api/PropertyController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/PropertyController.php)<br>[mobile_app/lib/features/discovery/data/smart_search_session.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/discovery/data/smart_search_session.dart)<br>[#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#137](https://github.com/JJalal1/real-estate-uat-backend/pull/137) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 10 — الحظر | الحظر الشخصي يمنع الرسائل والاتصال الجديد من الاتجاهين دون إتلاف التاريخ؛ فك الحظر لا يغير قرار الطرف الآخر. | مكتمل ومعتمد | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | اختبارات حظر متبادل وطرق بدء المحادثة والاتصال ورفض التجاوز؛ قفل PostgreSQL وتزامن قائم. يحتفظ الحظر بتاريخ المحادثات. HTTP/PG وحالات رفض واضحة؛ لا تحويل الحظر الشخصي إلى ban إداري. | [backend-api-runtime/app/Services/UserMessagingBlockService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/UserMessagingBlockService.php)<br>[backend-api-runtime/app/Http/Controllers/Api/AccountSafetyController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/AccountSafetyController.php)<br>[#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#143](https://github.com/JJalal1/real-estate-uat-backend/pull/143) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مكتمل ومعتمد | لا مانع خاص بالبند ضمن نطاقه المعتمد. |
| 12 — الصور المتكيفة | اختيار مشتق وفق مساحة العرض وDPR وmetered/Data Saver، وتكبير صريح دون تحميل أصل حساس. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | اختيار النسخة بالشاشة/DPR وتوفير البيانات، بروتوكول صور HTTP و304 وEXIF؛ تفاصيل العينة765344→194483B وبطاقة194483→39743B في القياس السابق المرتبط بالشفرة القائمة. Flutter/Laravel/Storage وقياس 304/بايتات؛ لا يساوي slow reader شبكة هاتف حقيقية. | [mobile_app/lib/core/network/adaptive_image_policy.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/network/adaptive_image_policy.dart)<br>[mobile_app/lib/features/properties/presentation/adaptive_property_photo.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/presentation/adaptive_property_photo.dart)<br>[backend-api-runtime/app/Services/ListingImageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingImageService.php)<br>[#119](https://github.com/JJalal1/real-estate-uat-backend/pull/119) [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 13 — التحميل الكسول | طلب وسائط العناصر المرئية فقط وإيقاف الطلبات عند المغادرة/التمرير السريع. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | بوابة viewport ومسار/تبويب، إلغاء وقوائم تدريجية؛ عينة21→2 طلب عند الفتح وعودة0 تنزيل إضافي. ليس قياس scroll FPS على مودم Android. قياس الفتح 21→2 طلب سابق مثبت وإعادة فحوص HTTP الحالية؛ العودة دون طلبات إضافية في السيناريو المقاس. | [mobile_app/lib/core/widgets/viewport_media.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/widgets/viewport_media.dart)<br>[mobile_app/lib/features/properties/presentation/adaptive_property_photo.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/presentation/adaptive_property_photo.dart)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 14 — التخزين المؤقت | TTL ومفاتيح فلاتر وحدود حجم وإبطال صحيح، وعزل حساب ومنع تخزين رد ملغى/سابق للطفرة. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | اختبارات الرد المتأخر والطلبات الملغاة وإبطال الكاش بعد التعديل؛ فصل الهوية في مخازن خاصة وردود HTTP حقيقية؛ إصلاح متانة عزل صفحة التحقيق ضمن PR158. اختبارات Dio/HTTP/ملفات محلية فعلية وعزل الحساب؛ كاش الوسائط لا يوسع صلاحيات الخادم. | [mobile_app/lib/core/network/api_client.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/network/api_client.dart)<br>[mobile_app/lib/features/properties/data/property_repository.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/data/property_repository.dart)<br>[mobile_app/lib/features/account/presentation/actor_scoped_page.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/account/presentation/actor_scoped_page.dart)<br>[#128](https://github.com/JJalal1/real-estate-uat-backend/pull/128) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 15 — التعافي من أخطاء الشبكة | حفظ العمل المؤكد والمدخلات عند timeout/503/429، retry الصحيح، ورفض النتائج القديمة ومسح البيانات عند فقد الصلاحية. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | 503/timeout/429 في الاختبارات وHTTP، إبقاء النص والصفوف عند الفشل العابر، ورفض نجاح كتابة وهمي؛ لا يفعّل استئناف البايتات11. HTTP 401/403/404/409/422/429 و503/timeout محاكاة حقيقية/مضبوطة؛ quota لكل حساب مع إبقاء حد login العام. | [mobile_app/lib/features/properties/data/property_repository.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/data/property_repository.dart)<br>[mobile_app/lib/features/discovery/data/smart_search_session.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/discovery/data/smart_search_session.dart)<br>[backend-api-runtime/app/Http/Middleware/AuthenticateApiToken.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Middleware/AuthenticateApiToken.php)<br>[#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#129](https://github.com/JJalal1/real-estate-uat-backend/pull/129) [#134](https://github.com/JJalal1/real-estate-uat-backend/pull/134) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 16 — حالات التحميل والفراغ والخطأ وإعادة المحاولة | حالات واضحة ومتناسقة عبر الرحلات الأساسية والشاشات المرتبطة، وفصل الصفر عن الخطأ وعدم ظهور بيانات حساب سابق. | يحتاج تجهيزًا إضافيًا | تدقيق واسع،70 حالة بيانات ل35 شاشة؛ اختبارات إضافية للنماذج والصفحات الخاصة؛ إصلاحretry والعزل والطلبات المتأخرة والتخطيط. إصلاح صفحة تحقيق الإعلان الداخلية وربطها بالحساب، وحجب الأدلة/الطلبات المتأخرة بعد الخروج والدخول بالحساب نفسه، وإصلاح تجاوز العنوان للشاشة. | 35 شاشة بيانات×وضعين=70 حالة، مع حالات إضافية للنماذج والصفحات الخاصة والبوابات؛ إجمالي156 حالة مركزة بعد PR158. inventory82 تعريف شاشة، لا نسبة تغطية82/82. الرحلات الأساسية CI/HTTP خضراء؛ إصلاح شاشتين لا يثبت تلقائيًا كل واجهة ثانوية. | [mobile_app/lib/core/widgets/app_components.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/widgets/app_components.dart)<br>[mobile_app/lib/features/admin/presentation/platform_settings_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/admin/presentation/platform_settings_screen.dart)<br>[mobile_app/lib/features/developments/presentation/development_admin_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/developments/presentation/development_admin_screen.dart)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#121](https://github.com/JJalal1/real-estate-uat-backend/pull/121) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#152](https://github.com/JJalal1/real-estate-uat-backend/pull/152) [#157](https://github.com/JJalal1/real-estate-uat-backend/pull/157) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 17 — تجميع علامات الخريطة | تجميع ثابت دون فقد/تكرار علامة، واحترام التكبير والعلامة المحددة والحدود. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | اختبار مستويات zoom8..19 وعدم فقد أو تكرار العلامات والعزل والفراغ؛ Native gestures والإطارات والضغط تحتاج هاتف المالك. سلامة Dart وEXPLAIN لفهرس location؛ rendering/gestures Native ليست نتيجة SQL. | [mobile_app/lib/features/map/domain/property_marker_cluster.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/map/domain/property_marker_cluster.dart)<br>[mobile_app/lib/features/map/presentation/map_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/map/presentation/map_screen.dart)<br>[#126](https://github.com/JJalal1/real-estate-uat-backend/pull/126) [#137](https://github.com/JJalal1/real-estate-uat-backend/pull/137) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 18 — الصفحات والتحميل التدريجي | صفحات مستقرة بلا تداخل، retry الصفحة الفاشلة، dedup وتوقف عند نهاية النتائج. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | HTTP صفحات وتراجع الصفحة الفاشلة وعدم التداخل؛ اختبارات البحث والدعم والرسائل؛ بقاء الصفحة الأولى وإعادة المحاولة المباشرة. الهاتف باقٍ. HTTP حقيقي وPG؛ العينة العامة لا تثبت كل قائمة خاصة على هاتف. | [mobile_app/lib/features/discovery/data/smart_search_session.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/discovery/data/smart_search_session.dart)<br>[mobile_app/lib/features/properties/data/property_repository.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/data/property_repository.dart)<br>[#129](https://github.com/JJalal1/real-estate-uat-backend/pull/129) [#137](https://github.com/JJalal1/real-estate-uat-backend/pull/137) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 19 — Debounce وإلغاء الطلبات | تأخير الطلب المناسب وإلغاء النقل ورفض الردود المعكوسة وعدم إعادة ملء الكاش بنتيجة ملغاة. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | Debounce وإلغاء/generation وردود معكوسة وتغيير فلتر/dispose؛ اختبارات منع استجابة بحث قديم وإبطال أدلة خاصة قديمة ضمن PR158. اختبارات تأخير/ردود معكوسة وإلغاء عبر Dio/HTTP؛ لا نتيجة قديمة تحل محل الجديدة. | [mobile_app/lib/core/network/api_client.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/network/api_client.dart)<br>[mobile_app/lib/features/discovery/data/smart_search_session.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/discovery/data/smart_search_session.dart)<br>[mobile_app/lib/features/developments/presentation/development_admin_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/developments/presentation/development_admin_screen.dart)<br>[#128](https://github.com/JJalal1/real-estate-uat-backend/pull/128) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 20 — Prefetch المشروط | يبقى OFF ما لم يثبت قياس فائدة صافية مع تكلفة بيانات وإشارة metered موثوقة. | OFF معتمد مشروط | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | محفوظ OFF وفق قرار المالك. لم نجمع تجربة مقارنة تشغيل جديدة تكفي لإثبات صافي فائدة الوقت/البايتات/الذاكرة؛ لا تفعيل تلقائي. القياسات الحالية تثبت viewport/cache وإعادة استخدام البايتات، ولا تثبت فائدة ON. | [mobile_app/lib/core/widgets/viewport_media.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/widgets/viewport_media.dart)<br>[mobile_app/lib/core/network/api_client.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/network/api_client.dart)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | OFF معتمد مشروط | يبقىOFF؛لا حاجة لاختبار تشغيل. |
| 22 — Deep Links وApp Links | قبول المسارات والأصول المسموح بها فقط، وHTTPS موثق بدومين وتوقيع رسميين وفتح Native صحيح. | يحتاج تجهيزًا إضافيًا | رفض بصمات assetlinks غير الكاملة أو package غير صالح؛ صيانة القائمة البيضاء للروابط دون اختراع هوية المتجر. | مسارات allowlist ورفض URI مشوه ومضيف/منفذ/اعتماد غير مسموح؛ assetlinks يقبل بصمات32-byte سليمة وحزمة reverse-DNS فقط. [] آمنة عند غياب الهوية الرسمية. عقود المسار والتحصين CI؛ ذلك لا يثبت ارتباط Android بالدومين. | [mobile_app/lib/router/app_deep_links.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/router/app_deep_links.dart)<br>[mobile_app/android/app/src/main/AndroidManifest.xml](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/android/app/src/main/AndroidManifest.xml)<br>[backend-api-runtime/app/Services/AndroidAppLinkAssociation.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/AndroidAppLinkAssociation.php)<br>[#123](https://github.com/JJalal1/real-estate-uat-backend/pull/123) [#133](https://github.com/JJalal1/real-estate-uat-backend/pull/133) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مانع خارجي محدد — غير جاهز للاعتماد النهائي | دومين HTTPS رسمي وبصمة شهادة Play والحزمة النهائية، ثم نشر assetlinks الحقيقي والتحقق من Android. روابط UAT والـcustom scheme لا تُعتمد بدل App Links الرسمية. |
| 23 — العقارات المشاهدة مؤخرًا | سجل محدود مرتب بلا تكرار ومعزول لكل حساب/زائر، مع كتابة ذرية وتعافي فشل الملفات. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | ملف منفصل لكل حساب/زائر، IO متسلسل وكتابة ذرية وحد30 ومنع التكرار ومحو؛ اختبارات فشل التخزين وإعادة المحاولة وعزل الحساب. تخزين محلي فقط؛ لا DB أو migration مطلوب؛ الملفات والردود المتأخرة واختبارات العزل مثبتة. | [mobile_app/lib/features/properties/data/recent_properties_store.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/data/recent_properties_store.dart)<br>[mobile_app/lib/features/properties/presentation/recent_properties_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/presentation/recent_properties_screen.dart)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 24 — حفظ حالة الاستكشاف والعودة إليها | الحفاظ على الفلاتر والخريطة والقائمة وسجل البحث بصورة ذرية مع عودة متسقة وعدم سباق كتابة. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | حفظ فلاتر/خريطة/سجل البحث متسلسل وذري، PageStorage وكاش؛ اختبارات حفظ متزامن وIO retry وعودة بلا تنزيل مكرر في العينة. filesystem حقيقي وHTTP عودة دون نقل إضافي في السيناريو المثبت. | [mobile_app/lib/features/map/data/property_discovery_history_store.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/map/data/property_discovery_history_store.dart)<br>[mobile_app/lib/features/map/presentation/map_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/map/presentation/map_screen.dart)<br>[#127](https://github.com/JJalal1/real-estate-uat-backend/pull/127) [#128](https://github.com/JJalal1/real-estate-uat-backend/pull/128) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 25 — تجربة عدم وجود نتائج | عرض الصفر كحالة صحيحة مع تعديل معايير واضح، وتمييزه عن HTTP فاشل أو قائمة قديمة. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | حالات no-results منفصلة عن خطأ الشبكة، تعديل/مسح الفلاتر؛ اختبارات Empty→503→Retry وUAT بعبارة اصطناعية لا تطابق شيئًا. HTTP 200 مع data=[] وmeta.total=0، وFlutter يفرق بينها وبين 503. | [mobile_app/lib/features/discovery/presentation/smart_search_assistant.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/discovery/presentation/smart_search_assistant.dart)<br>[mobile_app/lib/features/discovery/data/smart_search_session.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/discovery/data/smart_search_session.dart)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 26 — التحقق من تحديث التطبيق | قرار إجباري/اختياري صحيح حسب رقم البناء الفعلي، وفتح متجر مسموح وآمن وإتاحة تحديث رسمي متوافق. | يحتاج تجهيزًا إضافيًا | ربط رابط التحديث بمعرفالحزمة والتحقق منURI؛ نافذةإجباري قابلة للتمرير؛ تجهيز زوجبناء منمصدرواحد وتوقيع نفس العامل وفحصAPI36. | اختبارات optional/mandatory وإلزام رابط المتجر بمعرف الحزمة ورفض URI ضار؛ API36 A→B بنفس الشهادة مع مقارنة بصمات ملفَي مظهر واستعادة قبل/بعد الإطلاق دون شبكة. API/Flutter وبناء فعلي؛ API36 وELF/ZIP لا يغنيان عن اختبار upgrade موقع. | [mobile_app/lib/core/release/release_gate.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/release/release_gate.dart)<br>[backend-api-runtime/app/Http/Controllers/Api/ReleaseController.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Controllers/Api/ReleaseController.php)<br>[.github/workflows/broker-experience-ci.yml](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/.github/workflows/broker-experience-ci.yml)<br>[#131](https://github.com/JJalal1/real-estate-uat-backend/pull/131) [#139](https://github.com/JJalal1/real-estate-uat-backend/pull/139) [#141](https://github.com/JJalal1/real-estate-uat-backend/pull/141) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) [#156](https://github.com/JJalal1/real-estate-uat-backend/pull/156) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مانع خارجي محدد — غير جاهز للاعتماد النهائي | Package ID وشهادة إصدار مستقرة ومتجر ورابط إصدار رسميان، واختبار سياسة التحديث عبر Play. زوج UAT يثبت الاستبدال وحفظ ملفات محددة فقط، ولا يثبت تحديث جلسات موقعة/ترحيل قواعد كل إصدار سابق. |
| 27 — الصلاحيات عند الحاجة | طلب الموقع/الكاميرا/الميكروفون عند الاستخدام، مع رفض ودائم وخدمة متوقفة وعودة من الإعدادات دون إجبار. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | طلبات الأذونات عند الفعل ومسارات الرفض/الإعدادات؛ Manifest/built APK مستهدف36/min23. سلوك منتقي الصور والموقع ورفض الإذن في النظام يحتاج الهاتف. واجهات bridge ومواقف الرفض مختبرة بصورة آلية؛ نظام الإذن Native يحتاج جهازًا. | [mobile_app/lib/core/platform/app_permission_settings.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/platform/app_permission_settings.dart)<br>[mobile_app/lib/core/platform/stage5_media_picker.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/platform/stage5_media_picker.dart)<br>[mobile_app/lib/core/platform/voice_capture_controller.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/platform/voice_capture_controller.dart)<br>[#125](https://github.com/JJalal1/real-estate-uat-backend/pull/125) [#141](https://github.com/JJalal1/real-estate-uat-backend/pull/141) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 28 — خصوصية EXIF | لا تُعرض metadata الكاميرا/GPS الحساسة؛ أصل خاص، ترميز عرض نظيف واتجاه صحيح وعدم إتاحة variant=original. | مكتمل ومعتمد | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | ترميز المشتقات يحذف EXIF/GPS ويتعامل مع الاتجاه؛ JPEGs حية ومقارنة EXIF ورفض الأصل والوصول غير المصرح. صور الاختبار لا تتضمن بيانات بشرية. صور JPEG اصطناعية بوسم EXIF/GPS، غياب الوسم من العرض واتجاه محفوظ، رفض original422 وملكية404، bucket خاص. | [backend-api-runtime/app/Services/ListingImageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingImageService.php)<br>[backend-api-runtime/app/Services/ProfessionalPhotoService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ProfessionalPhotoService.php)<br>[backend-api-runtime/app/Services/CloudAssetStorageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/CloudAssetStorageService.php)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مكتمل ومعتمد | لا مانع خاص بالبند ضمن نطاقه المعتمد. |
| 29 — إدارة صور الإعلانات | ترتيب/رئيسية/حذف/استبدال وإعادة رفع آمنة، مع حماية المراجع ودون ملفات يتيمة من المسار المختبر. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. إصلاح صفحة تحقيق الإعلان الداخلية وربطها بالحساب، وحجب الأدلة/الطلبات المتأخرة بعد الخروج والدخول بالحساب نفسه، وإصلاح تجاوز العنوان للشاشة. | ترتيب/رئيسية/استبدال/حذف وملكية المسودة ومراجعة البصمة؛ HTTP وStorage حقيقيان واختبارات مراجعة الصور؛ لا موافقة موروثة لصورة جديدة. Flutter contracts وHTTP/PG/Storage حقيقي وصفر مراجع/أصول fixture بعد التنظيف؛ لا حذف لصور غير مستخدمي الاختبار. | [backend-api-runtime/app/Services/ListingEditorDraftService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingEditorDraftService.php)<br>[backend-api-runtime/app/Services/ListingImageService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingImageService.php)<br>[mobile_app/lib/features/properties/presentation/listing_editor_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/presentation/listing_editor_screen.dart)<br>[#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#140](https://github.com/JJalal1/real-estate-uat-backend/pull/140) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 30 — المسودات واستعادتها | checkpoint/revision مستقر واستعادة دون تكرار، وحماية التأخير وتبديل الحساب وحفظ العمل عند الشبكة الضعيفة. | مرشح لقبول المالك | مراجعة الاختبارات القائمة والحفاظ على التنفيذ؛ لم نعد بناءه. | محفوظات الجهاز وخادم المسودات وrevision/checkpoint، استعادة بعد فشل التخزين ورفض مسودة حساب آخر؛ مسودة وصورة خاصة معدتان في preflight. ليس TUS11. HTTP/PG وملفات وrevision، مع رفض قراءة حساب آخر وعدم تكرار ملف عند retry. | [backend-api-runtime/app/Services/ListingEditorDraftService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/ListingEditorDraftService.php)<br>[mobile_app/lib/features/properties/data/listing_account_draft_repository.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/data/listing_account_draft_repository.dart)<br>[mobile_app/lib/features/properties/presentation/listing_editor_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/properties/presentation/listing_editor_screen.dart)<br>[#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#140](https://github.com/JJalal1/real-estate-uat-backend/pull/140) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |
| 31 — حذف الحساب | حذف هوية وتوكنات/عمل عابر وإثباتات خاصة وأرشفة الإعلان، مع الاحتفاظ المحدد بالسجلات القانونية ورفض حذف الموظف بلا نقل صلاحيات. | يحتاج تجهيزًا إضافيًا | إغلاق سباقات المصادقة/OTP وإصدارtoken مع المحو؛ قفل المستخدم وإعادة فحص الحالة؛ اختباراتPostgreSQL؛ حساب حذف اصطناعي منفصل. | AccountErasureLaunchTest: فشلStorage يرجع بيانات المعاملة ثم نجاح retry، إلغاء الجلسات وحفظ المرجع المشترك. AuthRaceTest:5 سباقات؛ اختبارات PostgreSQL؛ لا حذف حساب بشري. HTTP/DB/Storage حقيقي لحساب اصطناعي؛ 401 بعد الحذف، أصل المسودة والصورة المهنية غائبان، المحاضر والرسائل المشتركة محفوظة وفق القواعد. | [backend-api-runtime/app/Services/AccountErasureService.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Services/AccountErasureService.php)<br>[backend-api-runtime/app/Http/Middleware/AuthenticateApiToken.php](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/backend-api-runtime/app/Http/Middleware/AuthenticateApiToken.php)<br>[mobile_app/lib/features/account/presentation/account_safety_screen.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/features/account/presentation/account_safety_screen.dart)<br>[#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#140](https://github.com/JJalal1/real-estate-uat-backend/pull/140) [#153](https://github.com/JJalal1/real-estate-uat-backend/pull/153) [#155](https://github.com/JJalal1/real-estate-uat-backend/pull/155) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | مانع خارجي محدد — غير جاهز للاعتماد النهائي | اعتماد سياسة الاحتفاظ والملفات المرتبطة بالإعلانات المؤرشفة، مزود OTP حقيقي للويب، صفحة حذف Production وقبول الهاتف. التنفيذ الداخلي يحتاج جلسة وعبارة تأكيد؛ OTP جديد موجود لمسار الويب وليس إلزاميًا داخل التطبيق. |
| 32 — الثيم والتناسق والاتجاه | ثيم فاتح/داكن/النظام محفوظ دون سباق وRTL وتكبير نص وتناسق مكونات وأصول معتمدة. | يحتاج تجهيزًا إضافيًا | 70 حالة light/dark معتكبيرالخط؛ نماذج بخطArabic الحقيقي؛ إصلاحFlex/metrics/القوائم والنوافذ وحقول الاختيار، ومناطق إدارية قابلة للتمرير. إصلاح صفحة تحقيق الإعلان الداخلية وربطها بالحساب، وحجب الأدلة/الطلبات المتأخرة بعد الخروج والدخول بالحساب نفسه، وإصلاح تجاوز العنوان للشاشة. | Light/dark وحجم2.4 وخط Noto Arabic وشاشات320×640/360×740؛ Flex/scroll/metrics/dialog/dropdown وprivate forms؛156 حالة مركزة مع header overflow72px مُصلح. API36 emulator ناجح، الهاتف باقٍ. تحليل Flutter وWidget وpreviews اصطناعية وفحص الأصول والخطوط داخل APK؛ أربع معاينات RTL كبيرة فُحصت بصريًا. | [mobile_app/lib/core/theme/theme_controller.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/theme/theme_controller.dart)<br>[mobile_app/lib/core/theme/app_theme.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/theme/app_theme.dart)<br>[mobile_app/lib/core/widgets/app_components.dart](https://github.com/JJalal1/real-estate-uat-backend/blob/44a5429d91827f2da73938b71c877c38572dd663/mobile_app/lib/core/widgets/app_components.dart)<br>[#124](https://github.com/JJalal1/real-estate-uat-backend/pull/124) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#152](https://github.com/JJalal1/real-estate-uat-backend/pull/152) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) [#157](https://github.com/JJalal1/real-estate-uat-backend/pull/157) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) | لم ينفذ هاتف فعلي؛ البناء 1340 موحد مع فحص محاكي API36. | جاهز وينتظر اختبار المالك على التطبيق | قبول المالك على Android فقط، وفق الخطوات الحالية. |

## تفسير الأعمال التسعة والأثر

### 2 — تحسين الصور والضغط والمشتقات

إنتاج نسخ عرض أصغر من الصورة الأصلية، بحجم وجودة يناسبان التطبيق. تستهلك القوائم بيانات أقل وتفتح الصور أسرع، مع إبقاء الأصل خارج الوصول العام.

إثبات OOM عند3 عمليات24MP داخل512MiB ثم قفل قبول غير حاجب503 قبلGD؛ نجاح العمليات الست؛ إصلاح مشاركة inode بينCLI وweb.

قياس Docker حقيقي: 24MP و512MiB و1CPU؛ فشل OOM baseline عند التزامن3، ثم 6/6 عمليات ناجحة بالتزامن1/2/3 دون OOM مع backpressure503. أقصى cgroup نحو357MiB؛ لا يعادل ذاكرة الهاتف.

**المتبقي:** قبول المالك على Android فقط، وفق الخطوات الحالية.

### 4 — العلامة المائية

إظهار هوية عقار على نسخة العرض وفق القرار والإعدادات المعتمدة. عند تفعيلها تُظهر مصدر الصورة وتدعم هوية المنصة، مع الحفاظ على خصوصية الأصل.

إعادة قياس مشتقات UAT وفحص عينة العلامة بصريًا؛ مفعلة أصلًا ولم نغيّر قرارها.

مشتقات UAT v2-wm وعينة اصطناعية مفحوصة بصريًا؛ watermark_active=true ورفض الأصل422 و304. العلامة كانت ON ولم نفعلها من جديد.

**المتبقي:** قبول المالك على Android فقط، وفق الخطوات الحالية.

### 5 — مشاركة العقارات

إرسال رابط العقار من التطبيق إلى تطبيقات التواصل عبر نافذة المشاركة الأصلية. يستطيع الباحث إرسال إعلان محدد لأهله أو عميله بدل وصفه أو إرسال صور منفصلة.

اختبارMethodChannel يثبت تغيّر العقار42 إلى84، وتعطيل مشاركة المسودة.

MethodChannel42→84 عند إعادة استخدام الواجهة، ومنع مشاركة المسودة؛ صفحة مشاركة UAT حقيقية للعقارات60–62. فتح التطبيقات الخارجية على الهاتف باقٍ.

**المتبقي:** قبول المالك على Android فقط، وفق الخطوات الحالية.

### 8 — الإشعارات

إبلاغ المستخدم بالرسائل والمراجعات والأحداث المهمة، داخل التطبيق وعلى الجهاز عند اعتماد الخدمة. الإشعارات الداخلية مفيدة الآن، لكن ذلك لا يثبت وصول تنبيه للجهاز وهو في الخلفية أو مغلق.

إعادة التحقق من الحالة والموافقة والجهاز قبل الإرسال، ومعالجةUNREGISTERED الدقيقة و429/5xx وإعادة المحاولة المحدودة ورصد قبول المزود دون ادعاء الهاتف.

10 اختبارات دورة إرسال: إعادة فحص المستخدم/الموافقة/الجهاز، UNREGISTERED دقيق، 429/5xx وRetry-After واستنفاد المحاولات. لا FCM هاتف فعليًا؛ devices=0 عند الفحص.

**المتبقي:** Firebase/FCM رسمي مطابق لهوية Android، إعداد أسراره بأمان، تشغيل عامل طابور فعلي مع queue=database، ثم إثبات وصول على هاتفين وسحب الموافقة. Push معطل الآن؛ حفظ الإشعار لا يثبت تسليمه.

### 16 — حالات التحميل والفراغ والخطأ وإعادة المحاولة

لكل رحلة مهمة عرض مفهوم أثناء الانتظار، وعند غياب البيانات أو رفض الوصول أو الفشل. يعرف المستخدم هل ينتظر أم يعدل المعايير أم يعيد المحاولة، ولا يرى نجاحًا وهميًا أو بيانات لا تخصه.

تدقيق واسع،70 حالة بيانات ل35 شاشة؛ اختبارات إضافية للنماذج والصفحات الخاصة؛ إصلاحretry والعزل والطلبات المتأخرة والتخطيط. إصلاح صفحة تحقيق الإعلان الداخلية وربطها بالحساب، وحجب الأدلة/الطلبات المتأخرة بعد الخروج والدخول بالحساب نفسه، وإصلاح تجاوز العنوان للشاشة.

35 شاشة بيانات×وضعين=70 حالة، مع حالات إضافية للنماذج والصفحات الخاصة والبوابات؛ إجمالي156 حالة مركزة بعد PR158. inventory82 تعريف شاشة، لا نسبة تغطية82/82.

**المتبقي:** قبول المالك على Android فقط، وفق الخطوات الحالية.

### 22 — Deep Links وApp Links

فتح عقار أو وجهة مدعومة من رابط خارجي داخل التطبيق مع احترام الدخول والصلاحية. يحافظ على ترابط المشاركة والإشعار والمتصفح مع التطبيق بدل ضياع المستخدم في صفحة عامة.

رفض بصمات assetlinks غير الكاملة أو package غير صالح؛ صيانة القائمة البيضاء للروابط دون اختراع هوية المتجر.

مسارات allowlist ورفض URI مشوه ومضيف/منفذ/اعتماد غير مسموح؛ assetlinks يقبل بصمات32-byte سليمة وحزمة reverse-DNS فقط. [] آمنة عند غياب الهوية الرسمية.

**المتبقي:** دومين HTTPS رسمي وبصمة شهادة Play والحزمة النهائية، ثم نشر assetlinks الحقيقي والتحقق من Android. روابط UAT والـcustom scheme لا تُعتمد بدل App Links الرسمية.

### 26 — التحقق من تحديث التطبيق

معرفة ما إذا كان الإصدار يحتاج تحديثًا اختياريًا أو إلزاميًا، وفتح الوجهة الصحيحة. يمكن معالجة إصدار قديم غير متوافق، لكن إعداد تحديث رسمي خاطئ قد يحبس المستخدم أو يرسله لوجهة غير موثوقة.

ربط رابط التحديث بمعرفالحزمة والتحقق منURI؛ نافذةإجباري قابلة للتمرير؛ تجهيز زوجبناء منمصدرواحد وتوقيع نفس العامل وفحصAPI36.

اختبارات optional/mandatory وإلزام رابط المتجر بمعرف الحزمة ورفض URI ضار؛ API36 A→B بنفس الشهادة مع مقارنة بصمات ملفَي مظهر واستعادة قبل/بعد الإطلاق دون شبكة.

**المتبقي:** Package ID وشهادة إصدار مستقرة ومتجر ورابط إصدار رسميان، واختبار سياسة التحديث عبر Play. زوج UAT يثبت الاستبدال وحفظ ملفات محددة فقط، ولا يثبت تحديث جلسات موقعة/ترحيل قواعد كل إصدار سابق.

### 31 — حذف الحساب

إيقاف الحساب ومحو هويته وبياناته القابلة للحذف وفق قواعد الاحتفاظ المعتمدة. لا تبقى ملفات خاصة مؤقتة مهملة، ولا يعود الحساب لاستخدام الرمز نفسه بعد الحذف.

إغلاق سباقات المصادقة/OTP وإصدارtoken مع المحو؛ قفل المستخدم وإعادة فحص الحالة؛ اختباراتPostgreSQL؛ حساب حذف اصطناعي منفصل.

AccountErasureLaunchTest: فشلStorage يرجع بيانات المعاملة ثم نجاح retry، إلغاء الجلسات وحفظ المرجع المشترك. AuthRaceTest:5 سباقات؛ اختبارات PostgreSQL؛ لا حذف حساب بشري.

**المتبقي:** اعتماد سياسة الاحتفاظ والملفات المرتبطة بالإعلانات المؤرشفة، مزود OTP حقيقي للويب، صفحة حذف Production وقبول الهاتف. التنفيذ الداخلي يحتاج جلسة وعبارة تأكيد؛ OTP جديد موجود لمسار الويب وليس إلزاميًا داخل التطبيق.

### 32 — الثيم والتناسق والاتجاه

تناسق المظهر الفاتح والداكن واتجاه العربية وحفظ اختيار المستخدم. لا يتبدل اختيار المستخدم بسبب رد قديم، وتصبح الرسائل والأزرار والتباعد والاتجاه أكثر اتساقًا.

70 حالة light/dark معتكبيرالخط؛ نماذج بخطArabic الحقيقي؛ إصلاحFlex/metrics/القوائم والنوافذ وحقول الاختيار، ومناطق إدارية قابلة للتمرير. إصلاح صفحة تحقيق الإعلان الداخلية وربطها بالحساب، وحجب الأدلة/الطلبات المتأخرة بعد الخروج والدخول بالحساب نفسه، وإصلاح تجاوز العنوان للشاشة.

Light/dark وحجم2.4 وخط Noto Arabic وشاشات320×640/360×740؛ Flex/scroll/metrics/dialog/dropdown وprivate forms؛156 حالة مركزة مع header overflow72px مُصلح. API36 emulator ناجح، الهاتف باقٍ.

**المتبقي:** قبول المالك على Android فقط، وفق الخطوات الحالية.

## حزمة Android الحالية

| الخاصية | B الحالية | A السابقة المتوافقة |
|---|---|---|
| Build | 1340 | 1339 |
| SHA256 | `c0a01aad16e0ab82faf96c7007a0f0b1d746206c85fd791d9d51157e8dbfafb6` | `383a626d86a44970bcdf3b5852ab12f6a6dac8948412d10238810e93d6e004c7` |
| bytes | 118222826 | 118222844 |
| شهادة SHA256 | `58b02159621181d4b63d2483bf5d610da2f1595a918afde8f39109c68d916578` | نفس الشهادة |
| Package / versionName | `com.example.real_estate_mobile` / `0.1.0` | نفسه |
| API | `https://real-estate-uat-api-frankfurt.onrender.com/api` | نفسه |
| min / target | 23 / 36 | نفسه |

كلتاهما من مصدر واحد بالشهادة نفسها على عامل CI نفسه. ثُبتت A ثم استُبدلت بـB على API36 emulator، وفُحص hash ملفَي مظهر واستعادة قبل/بعد تشغيل دون شبكة، وعدم الانهيار. لا يثبت ذلك جلسة تسجيل دخول حقيقية أو ترحيل كل مخطط بيانات أو تحديث Play الرسمي. Kernel المحاكي 4096 بايت؛ نجاح 16KB هو فحص ELF وZIP alignment وليس تشغيل kernel16KB. لا هاتف فعلي ولا ادعاء تسليم FCM.

- حزمة المستلم: `Aqer_Owner_UAT_1339_1340_Encrypted.zip`؛ SHA256 `3eee7c265b4e30e105a2254a94ea5b79038f4d4aadfacbd464e296bdaa232074`.
- المستودع عام وسياسة تسليمه recipient-encrypted CMS فقط. لا APK plaintext منشور في artifacts العامة. المفتاح الخاص يبقى عند المستلم؛ لا يُطلب في المحادثة.
- استخدم `scripts/decrypt_owner_uat_package.py` وREADME العربي المرفق؛ الأداة تثبت hash ZIP قبل فك أي جزء، وتثبت source/package/native proof وتوافق الشهادة والأرقام المتتالية، ثم تستخرج owner-access.json محليًا بصلاحية600.
- للتجربة العادية ثبّتB. لتجربة التحديث فقط ثبّتA واحفظ مسودة وثيمًا ثمB دون إزالةA. مع نسخة1285 أو UAT قديمة بشهادة مختلفة، استخدم ملف Android/جهاز اختبار منفصلًا ولا تحذف مسوداتك.
- Universal UAT بثلاث معماريات قرابة118MB، وزوج مشفر قرابة236MB. تقسيمات AAB للمتجر غير مبنية بهوية رسمية بعد.

## البيئة وبيانات القبول

- Render `real-estate-uat-api-frankfurt`، نشر `dep-dbfl0h67bikc73dvfmhg`؛ Live على `44a5429d91827f2da73938b71c877c38572dd663`، autoDeploy OFF.
- Supabase UAT `ipxsgxsqzthpgthwvdno`، PostgreSQL17/PostGIS،59 هجرة،0bucketعام،جدول11 غائب. لا تعديل مخطط أو RLS/GRANT في هذه الدفعة.
- بصمات السجلات المالية المحمية قبل/بعدV5 متطابقة: payments `51860ba57ad71dc7a6629ccfba084d8a`، sai_terms `77453f6664656c4b1c6ef27a4d6f3268`، attestations `0ee0c66db7ea92fda848213bd4e776ae`، receivables `45aea29a39a30e3f2477e166bb2cf0f2` عند cutoff `2026-10-24T23:48:00Z`. ليست backup/restore أو فحصًا لكل جداول المنصة.
- ستة أدوار قائمة اصطناعية + حساب حذف منفصل. التحقق عبر OTP login/me وواجهات الأدوار الحقيقية، ورفض403 للمستخدم في الإدارة و404 للمسودة الأجنبية.
- عقارات منشورة60/61/62، إعلان مراجعة `93` بصورتين، مسودة استعادة `29e4ec63-e136-47b4-ac22-7da1c00eb420`، وحساب حذف `66`. جلسات الفحص نفسها سُحبت، والبيانات تبقى لقبول المالك.
- الرسائل الاصطناعية بين user26 وbroker28 في thread15 و20 متاحة؛ لم تُستخدم بيانات بشرية. بيانات الدخول داخل كبسولة مشفرة فقط.
- المحاولةowner-v1 توقفت429 وأُبقي إيصالها ناقصًا؛ v2 يحترم Retry-After ولا يخفف middleware ولا يعيد كتابة الإعلان. استعاد فقط حسابها الفارغ المثبت بتدقيق وهوية وصلاحيات وعدّ مراجع خالية؛ أي اصطدام يرفض دون تعديل.

## دليل قبول المالك — كل بند

### 1 — ملاءمة صور العقار ومراجعتها

**الحساب:** الوسيط ثم المراجع

**الخطوات:** افتح إعلان «اختبار المالك — مراجعة الصور»؛ أرسل للمراجع/افتح الوارد واستلم المهمة؛ صنّف صورة المكتب مناسبة والنمط الملون غير مناسب، وأعد الإعلان بسبب واضح. بدّل الصورة من حساب الوسيط وأعد الإرسال، ثم راجع النسخة الحالية.

**النجاح:** الصور غير المراجعة أو غير المناسبة تمنع النشر؛ الاستبدال يلغي القرار القديم ويحتاج مراجعة جديدة.

**الفشل والرفض:** جرّب اعتماد الإعلان قبل مراجعة كل الصور، وفتح المهمة من حساب دعم آخر.

### 2 — تحسين الصور والضغط والمشتقات

**الحساب:** الوسيط

**الخطوات:** أضف صور الاختبار 24MP إلى مسودة فقط؛ جرّب صورة عادية ثم مدوّرة، ثم عدة صور. انتقل بين المعرض والبطاقة والتفاصيل، وأعد المحاولة إن ظهرت رسالة انشغال.

**النجاح:** عرض بالاتجاه الصحيح، ونسخ عرض أصغر؛ نجاح واضح دون توقف التطبيق؛ 503 المحتمل مؤقت ولا يُحسب حفظًا ناجحًا.

**الفشل والرفض:** صورة تالفة، ملف أكبر من 8MiB، انقطاع أثناء الرفع؛ يجب ألا يتكرر الحفظ أو تضيع المسودة. قياس ذاكرة الهاتف نفسه لا يستنتج من قياس الخادم.

### 4 — العلامة المائية

**الحساب:** زائر

**الخطوات:** افتح العقارات 60 و61 و62 ثم الصورة المكبرة، وقارن عينة العلامة المرفقة.

**النجاح:** تظهر علامة عقار المعتمدة دون حجب التفاصيل الأساسية؛ الأصل الخاص غير قابل للوصول العام.

**الفشل والرفض:** راجع العلامة في الوضعين الفاتح والداكن وعلى شبكة ضعيفة؛ لا تغير إعداد التشغيل.

### 5 — مشاركة العقارات

**الحساب:** زائر

**الخطوات:** افتح العقار60 ثم اضغط مشاركة وأرسله إلى تطبيق تختاره؛ كرر للعقار61؛ افتح الرابط من التطبيق الخارجي.

**النجاح:** المحتوى والعنوان والرابط يخصان العقار الحالي؛ صفحة UAT الخارجية قابلة للفتح.

**الفشل والرفض:** لا مشاركة لمسودة؛ جرّب عقارًا لم يعد متاحًا. وصول رابط HTTPS مباشرة إلى التطبيق يحتاج App Links الرسمية في22.

### 6 — منع الإعلانات المكررة

**الحساب:** الوسيط

**الخطوات:** فحص تراجع اختياري: حاول إنشاء إعلان جديد للهوية الفيزيائية نفسها دون تغيير الدور أو الوحدة.

**النجاح:** يمنع النظام تكرار العقار أو تمثيله من معلن آخر؛ تغيير الغرض لا يجيز إعلانًا مكررًا.

**الفشل والرفض:** لا تغيّر الاختبارات أو أرقام الهوية للتحايل على الرفض.

### 7 — البلاغات والإشراف

**الحساب:** المستخدم ثم الدعم

**الخطوات:** بلّغ عن إعلان أو محادثة اصطناعية، ثم افتح الوارد بالدعم واستلم البلاغ وسجل القرار.

**النجاح:** بلاغ واحد قابل للتتبع وملكية مهمة واضحة؛ فتح الرسائل الخاصة يحتاج صلاحية مستقلة ويسجل.

**الفشل والرفض:** حاول فتح محتوى خاص من حساب لا يملك الصلاحية؛ يجب أن يرفض. لا تفحص محادثات بشرية.

### 8 — الإشعارات

**الحساب:** حسابان وهاتفان عند تفعيل الخدمة الرسمية

**الخطوات:** يمكن الآن اختبار قائمة الإشعارات والتفضيلات. بعد ربط Firebase والعامل، امنح الإذن، أنشئ حدثًا للحساب الثاني، واختبر المقدمة والخلفية ثم تسجيل الخروج.

**النجاح:** القائمة الداخلية تحفظ الحدث؛ التسليم للهاتف يُثبت منفصلًا، مع منع الإرسال بعد سحب الموافقة أو تعطيل الحساب.

**الفشل والرفض:** 429 و5xx وإعادة المحاولة مثبتة بمحاكاة المزود؛ FCM معطل حاليًا ولا يُتوقع Push حقيقي في هذه النسخة.

### 9 — البحث العربي

**الحساب:** زائر

**الخطوات:** ابحث عن «إب» ثم «اب»، وبدّل المحافظة والنوع والغرض والترتيب، ثم عد إلى النتائج.

**النجاح:** نتائج متسقة مع التطبيع والفلاتر، مع إظهار المعايير الحالية.

**الفشل والرفض:** بحث لا يطابق شيئًا ثم انقطاع الشبكة: الفراغ يختلف عن الخطأ؛ الصوت تابع لإذن/خدمة مستقلة.

### 10 — الحظر

**الحساب:** المستخدم وحساب آخر

**الخطوات:** فحص تراجع اختياري: افتح محادثة اصطناعية واحظر الطرف الآخر، وحاول بدء محادثة/رسالة من الطرفين ثم ألغِ الحظر.

**النجاح:** يُطبق الحظر في الخادم؛ تبقى المحادثات السابقة ولا تسمح معرّفات بديلة بتجاوزه.

**الفشل والرفض:** اختبر حظر الطرفين وإلغاء حظر طرف واحد؛ لا يكفي ذلك إذا بقي حظر من الطرف الآخر.

### 12 — الصور المتكيفة

**الحساب:** زائر

**الخطوات:** افتح قائمة ثم تفاصيل وصورة مكبرة على اتصال جيد وضعيف، مع Data Saver وتشغيل توفير البيانات.

**النجاح:** البطاقة تستخدم صورة مناسبة لحجمها؛ التحميل الأعلى جودة عند الحاجة/الطلب، وتظل الملامح واضحة.

**الفشل والرفض:** انتقل سريعًا قبل انتهاء الصور؛ لا تظهر صورة عقار سابق أو يحمل حجمًا كاملًا بلا حاجة.

### 13 — التحميل الكسول

**الحساب:** زائر

**الخطوات:** افتح قائمة طويلة ومرر ببطء ثم بسرعة وارجع للأعلى.

**النجاح:** صور ما يظهر تُحمّل تدريجيًا؛ الرجوع يستفيد من الكاش.

**الفشل والرفض:** انقطاع وسط التمرير ثم عودة الشبكة وإعادة المحاولة دون بطاقات مكسورة دائمة.

### 14 — التخزين المؤقت

**الحساب:** المستخدم ثم الوسيط

**الخطوات:** افتح بيانات عقار ثم حدّثها من حساب الوسيط وعد إلى القائمة والتفاصيل؛ بدّل الحساب.

**النجاح:** البيانات المتجددة لا يستبدلها رد قديم؛ لا تبقى بيانات خاصة بالحساب السابق.

**الفشل والرفض:** ابدأ طلبًا بطيئًا، غيّر الفلتر أو سجل الخروج قبل انتهائه؛ النتائج القديمة لا تعود.

### 15 — التعافي من أخطاء الشبكة

**الحساب:** المستخدم والوسيط

**الخطوات:** افتح شاشة ثم افصل الاتصال، أعد المحاولة، وأعد الشبكة. جرّب حفظ مسودة عند انقطاع الاتصال.

**النجاح:** رسالة واضحة وفعل إعادة محاولة يعمل؛ الحفظ الفاشل لا يعرض نجاحًا كاذبًا.

**الفشل والرفض:** 503 و429 والمهلة آليًا؛ على الهاتف جرّب وضع الطيران ثم الرجوع دون فقد النص.

### 16 — حالات التحميل والفراغ والخطأ وإعادة المحاولة

**الحساب:** كل الأدوار

**الخطوات:** اتبع سجل الشاشات المرفق: صفحة بيانات، حالة فارغة، انقطاع، إعادة المحاولة، ثم الخروج وتبديل الحساب.

**النجاح:** لا شاشة تحميل دائمة أو نص استثناء تقني أو زر معطل بلا تفسير؛ أخطاء الشبكة قابلة للتعافي.

**الفشل والرفض:** شاشات التفاصيل والنماذج ومناطق الإدارة والنوافذ؛ الصلاحية المرفوضة لا تعرض بيانات قديمة. الخريطة الأصلية تحتاج القبول المباشر.

### 17 — تجميع علامات الخريطة

**الحساب:** زائر

**الخطوات:** افتح الخريطة، كبّر وصغّر واضغط تجمعًا ثم علامة منفردة؛ ارجع للقائمة.

**النجاح:** التجمعات تتغير مع مستوى التكبير وتفتح العقار الصحيح دون تجمد ملحوظ.

**الفشل والرفض:** كرر على هاتف محدود الذاكرة واتصال ضعيف؛ قياس سلاسة Native لم يُستبدل باختبار Widget.

### 18 — الصفحات والتحميل التدريجي

**الحساب:** المستخدم والوسيط والدعم

**الخطوات:** مرر نتائج البحث والإعلانات والوارد حتى الصفحة التالية؛ افصل الشبكة عند تحميل صفحة لاحقة ثم أعدها واضغط إعادة المحاولة.

**النجاح:** الصفحة الأولى تبقى؛ تعاد الصفحة الفاشلة ويكمل التصفح دون تكرار أو فقد الصفوف.

**الفشل والرفض:** غير الفلتر أثناء تحميل صفحة لاحقة؛ لا تختلط صفحات البحثين.

### 19 — Debounce وإلغاء الطلبات

**الحساب:** زائر

**الخطوات:** اكتب البحث بسرعة، وغيّر النوع والمحافظة عدة مرات مع اتصال بطيء.

**النجاح:** النتيجة النهائية تطابق آخر طلب فقط؛ لا تومض نتائج طلب ملغى.

**الفشل والرفض:** ارجع قبل انتهاء الطلب وأعد فتح البحث؛ لا استثناء بعد إغلاق الشاشة.

### 20 — Prefetch المشروط

**الحساب:** قرار التشغيل

**الخطوات:** لا تفعّل Prefetch في هذه الجولة. راقب سلوك التصفح العادي فقط.

**النجاح:** يبقى OFF بالقرار المعتمد حتى تجربة تُثبت صافي فائدة الوقت مقابل البايتات والذاكرة.

**الفشل والرفض:** لا نختبر تفعيله على اتصال المالك المدفوع لمجرد إغلاق بند.

### 22 — Deep Links وApp Links

**الحساب:** زائر ومستخدم مسجل

**الخطوات:** جرّب realestate://app/properties/60 وروابط UAT من خارج التطبيق، في حال الإغلاق والفتح وتسجيل الدخول.

**النجاح:** الرابط المسموح يفتح الوجهة الصحيحة؛ الروابط المزيفة أو المشوهة تُرفض.

**الفشل والرفض:** HTTPS App Links التلقائية تنتظر دومين وشهادة Play حقيقيين؛ لا يُعلن اعتمادها بمجرد custom scheme.

### 23 — العقارات المشاهدة مؤخرًا

**الحساب:** المستخدم ثم حساب آخر

**الخطوات:** افتح عدة عقارات؛ افتح «شوهد مؤخرًا» وأغلق التطبيق وافتحه، ثم بدّل الحساب وامسح السجل.

**النجاح:** ترتيب وحد30 دون تكرار، محفوظ على الجهاز ومعزول حسب الحساب/الزائر.

**الفشل والرفض:** لا يظهر سجل الحساب الأول للثاني، وفشل التخزين لا يوقف فتح العقار.

### 24 — حفظ حالة الاستكشاف والعودة إليها

**الحساب:** زائر

**الخطوات:** حدد فلاتر وموضع خريطة وابحث؛ افتح عقارًا ثم ارجع؛ أغلق التطبيق وافتحه.

**النجاح:** تعود حالة الاستكشاف والفلاتر المتوقعة دون إعادة ضبط أو تنزيل زائد غير مبرر.

**الفشل والرفض:** عد أثناء طلب متأخر وكرر الحفظ السريع؛ الحالة الأحدث تبقى.

### 25 — تجربة عدم وجود نتائج

**الحساب:** زائر

**الخطوات:** ابحث بعبارة «zzzz-owner-no-match-20261026»، ثم عدّل المعايير أو امسحها.

**النجاح:** رسالة عدم وجود نتائج مع طريق واضح لتعديل البحث، وليست رسالة عطل.

**الفشل والرفض:** افصل الإنترنت: يظهر خطأ وإعادة محاولة بدل الادعاء أن النتائج صفر.

### 26 — التحقق من تحديث التطبيق

**الحساب:** المالك — زوج UAT

**الخطوات:** ثبّت النسخة A ثم احفظ مسودة ومظهرًا؛ حدّث إلىB المتوافقة في الشهادة دون إزالةA؛ تحقق من البيانات. بوابتا الاختياري والإجباري لهما اختبارات آلية مستقلة.

**النجاح:** زيادة رقم البناء وبقاء الملفات الخاصة؛ الاختياري يمكن تأجيله، والإجباري يمنع الاستمرار عندما يكون هناك رابط متجر صحيح.

**الفشل والرفض:** الزوج من المصدر نفسه دليل ميكانيكية تحديث UAT؛ تحديث Play وقبول السياسة النهائية يحتاجان هوية المتجر والتوقيع الرسميين.

### 27 — الصلاحيات عند الحاجة

**الحساب:** المستخدم

**الخطوات:** اضغط «موقعي» أو إضافة صورة حين تحتاجها فقط؛ ارفض الإذن، ثم ارفض دائمًا وعد من إعدادات النظام.

**النجاح:** لا أذونات مفاجئة عند البداية؛ رفض مفهوم وخيار إعدادات اختياري؛ تعمل المحاولة بعد منح الإذن.

**الفشل والرفض:** اختبر تعطيل خدمة الموقع وAndroid13+ للإشعارات عند تفعيلFCM لاحقًا.

### 28 — خصوصية EXIF

**الحساب:** الوسيط

**الخطوات:** فحص تراجع اختياري: ارفع صورة EXIF اصطناعية ثم افتح مشتقات العرض العامة.

**النجاح:** بيانات الكاميرا/GPS محذوفة من العرض؛ الاتجاه صحيح؛ موضع العقار يأتي من اختيار المستخدم.

**الفشل والرفض:** الأصل الخاص/إثبات الملكية غير عام؛ لا تستخدم صورة وثيقة بشرية للفحص.

### 29 — إدارة صور الإعلانات

**الحساب:** الوسيط ثم المراجع

**الخطوات:** على الإعلان الاصطناعي غيّر ترتيب الصور والرئيسية، احذف واحدة واستبدل أخرى، ثم احفظ وأعد فتحه.

**النجاح:** الترتيب والرئيسية محفوظان، والصورة المستبدلة تحتاج مراجعة جديدة.

**الفشل والرفض:** افصل الاتصال أثناء الحفظ، وأعد المحاولة، وافتح مسودة من الحساب الآخر للتأكد من الرفض.

### 30 — المسودات واستعادتها

**الحساب:** الوسيط

**الخطوات:** افتح مسودة الاستعادة المعدّة؛ اكتب نصًا وأضف صورة؛ احفظ أو اترك استعادة الجهاز، أغلق التطبيق قسرًا ثم افتحه وأكمل.

**النجاح:** النص والترتيب والصور المحفوظة تعود للحساب نفسه، وتظهر نتيجة الحفظ بوضوح.

**الفشل والرفض:** انقطاع الرفع/الخروج/نقر استعادة مرتين/تبديل الحساب؛ لا يفتح محرران ولا تضيع النسخة الأحدث. هذا ليس استئناف البايتات11.

### 31 — حذف الحساب

**الحساب:** حساب الحذف الاصطناعي فقط

**الخطوات:** استعمل حساب الحذف المنفصل في كبسولة الوصول؛ أنشئ بيانات اصطناعية، افتح الحذف واقرأ الأثر، ثم أكّد العبارة؛ حاول استعمال الجلسة القديمة.

**النجاح:** تمحى الهوية وتلغى الجلسات وتزال وثائق التحقق والمسودات غير المشتركة؛ تؤرشف الإعلانات وتُحفظ مراجعها والسجلات المشتركة وفق السياسة المطلوب اعتمادها. لا تعني العملية مسح كل ملف مرتبط بإعلان مؤرشف.

**الفشل والرفض:** فشلStorage/سباقاتOTP مثبتة آليًا؛ سياسة الاحتفاظ ومزودOTP وصفحة حذف الإنتاج لا تزال موافقات خارجية. لا تحذف حساب وسيط أو دعم أو حسابًا بشريًا.

### 32 — الثيم والتناسق والاتجاه

**الحساب:** كل الأدوار

**الخطوات:** غيّر الفاتح والداكن والنظام ثم أعد الفتح؛ جرّب حجم خط2.4 وشاشة صغيرة؛ راجع العناوين والأزرار والنوافذ والعودة وRTL.

**النجاح:** ثيم محفوظ، قراءة واضحة، اتجاه وتنقل متسقان، ومحتوى قابل للوصول مع تكبير الخط.

**الفشل والرفض:** افتح لوحة الإدارة/التوثيق/التحديث/المناطق؛ تحقق من شريطي النظام ولوحة المفاتيح علىAPI36 ومن جهاز أقدم.

## الأمان وحذف الحساب والتكامل

الخادم صاحب قرار المصادقة والملكية والدور، مع اختبارات رفض IDOR/BOLA ومسودات/صور/بلاغات ورسائل. شملت التقوية حسابًا يتبدل أثناء قراءة token أو انتظارHTTP، وصفحات MaterialPageRoute خاصة ونوافذ الجذر. سجّل static inventory82 تعريف شاشة مرجعية في مسار الاستيراد الفعال، وهو ليس ادعاء82/82 تجربة هاتف أو تغطية سلوكية. الملف المرفق يبين المراجع والدلائل والواجهات الأصلية التي تحتاج قبولًا بشريًا.

حذف الحساب الداخلي يتطلب جلسة وعبارة تأكيد. حذف الويب يتطلب OTP لغرض الحذف وsession محمية. يمحو AccountErasureService الهوية والجلسات والتحديات والأجهزة والبيانات المؤقتة ووثائق التحقق ومسودات غير مشتركة، ويؤرشف الإعلانات ويمحو حقول الاتصال/الملكية التعريفية. يحفظ مراجع ملفات ما زالت مرتبطة بإعلان مؤرشف والسجلات المالية والعقود والتدقيق والرسائل المشتركة. لا محو شامل ولا مدد احتفاظ مخترعة؛ هذه سياسة باقية على الاعتماد. فشلStorage يمنع نجاحًا كاذبًا ويرجعDB metadata لإعادة المحاولة؛ البايتات التي حُذفت بالفعل ليست معاملة موزعة قابلة للرجوع.

FCM يبقىOFF؛QUEUE_CONNECTION الحاليةsync ولا عامل حي معتمد. قبل التفعيل: إعداد هويةFirebase الرسمية في Android، وحساب خدمة الخادم عبر مدير الأسرار، وضبطqueue=database والعامل ومراقبة التسليم والفشل وإيقافه عند rollback. لا يعتبر حفظ إشعار أو provider accepted إثباتًا للهاتف.

## الأداء109 وقابلية التوسع

- الصور: baseline512MiB/1CPU قتل عاملًا137 عند ثلاث24MP؛ بعد الإصلاح6/6 (1/2/3تزامن) دونOOM. أعلى cgroup374710272B≈357.35MiB. القفل per-runtime يسلسلGD، ولا يثبت سعة عدة replicas أو RAM الهاتف.503 مؤقت قبل الكتابة مع Retry-After2.
- المعزول:10kعقار/50مالك/20kmetadataصور،270HTTP،تزامن1/3/6،0أخطاء. p95عند6:first244.33ms/deep315.87/Arabic901.18/market796.93/nearby917.90. لا بايتات صور ولاRender في هذه التجربة؛18عينةللمجموعة تعني أن p95/p99 قريبان من أقصاها وليسا tail طويل المدة.
- UATV5: p50=262ms/p95=2894ms/p99=5025ms ل118طلبًا مختلطًا loopback،وليسWAN أوsearchSLO. قياسRenderHTTPغيركافٍ. Issue109 يبقى مفتوحًا.
- خطوة التوسع: بيئة معزولة بموارد مماثلة للإنتاج وحمل متدرج ومدة/إحماء كافيين،مع CPU/RSS/DB connections/queue age/error rate/bytes/p50/p95/p99. يُزادcomputeأو العامل أو الكاش أو فهارس الاستعلام المقاس بناءً على الاختناق،لا ادعاء بملايين مستخدمين.

## مخاطر وبوابات

| الأولوية | الحالة |
|---|---|
| P0 | لا P0 مثبت باقٍ في الرحلات المفحوصة؛ ليست شهادة خلو كل النظام من كل ثغرة. |
| P1 أُغلق | OOM24MP؛ سباقات إحياء الحساب؛ عزل بيانات ونوافذ وطلبات حساب سابق؛ lifecycleFCM الدقيق، مع اختبارات تراجع. |
| P1 باقٍ | الهاتف،109،النسخ/الاستعادة،الخدمات والهوية والتوقيع والسياسات والتشغيل؛ تمنع GO. |
| P2 | تقليل حجم التنزيل عبرAABالرسمي،توسيع عينات الأجهزة والقياسات وتحسينات تتبع ملاحظات القبول؛ لا خفض خطورة P1. |

| بوابة | الحالة | الدليل/العمل الباقي |
|---|---|---|
| المصدر الموحد وCI | مستوفى ضمن النطاق | دمجات صغيرة ومراجعة فروق مع تطابق الشجرة وبناء موثق؛ الوثائق اللاحقة لا تغير ثنائية APK. |
| عقود API وقاعدة البيانات | مستوفى ضمن النطاق | Laravel/SQLite وPostgreSQL17/PostGIS واختبارات رفض الملكية والتزامن؛59 هجرة قائمة دونDDL جديد. |
| فحص UAT عبر HTTP | مستوفى ضمن النطاق | V5:170 تحققًا/118HTTP/cleanup true، وتجهيز المالك v2 مستقل بإيصال محفوظ. |
| الخصوصية والعزل والملفات | مستوفى ضمن النطاق | مخزن خاص، رفض أصل الصورة وطلبات حساب آخر؛ إغلاق سباقات المصادقة والعزل المتأخر. ليست شهادة خلو مطلق من الثغرات. |
| الصور الكبيرة وحدود الذاكرة | مستوفى ضمن النطاق | فشل موثق قبل الإصلاح ثم6/6 بالتزامن المحدود دونOOM داخل512MiB؛503 عند الانشغال مقصودة. |
| فحص بناء Android وتحديث UAT | مستوفى ضمن النطاق | حزمة موحدة،توقيع متوافق للزوج وAPI36 emulator و16KB static checks؛لا هاتف فعلي. |
| قبول Android من المالك | باقٍ | المراجعة البشرية والصور والخريطة والأذونات والشبكة والأدوار والتحديث على الهاتف لم تنفذ من المالك بعد. |
| الأداء109 وسعة الإنتاج | باقٍ | 10k isolated وUAT samples فقط؛لا providerp95 كافٍ أو حمل إنتاج متدرج مع ميزانية الموارد. |
| النسخ والاستعادة المستقلة | باقٍ | بصمات السجلات ليست backup؛يلزم نسخ كامل مشفر واستعادة معزولة وفحص الملفات والعلاقات. |
| FCM وعامل وإثبات الهاتف | باقٍ | PushOFF،لا عامل فعلي معتمد أو تسليم هاتفين؛قبول المزود لا يعني وصول الجهاز. |
| OTP رسمي | باقٍ | UATallowlist ليست مصادقة Production؛المزود والاعتمادات خارج المحادثة. |
| الدومين وAppLinks | باقٍ | لا دومين رسمي وبصمة Play معتمدان؛[] متوقعة عند غيابهما. |
| هوية Play والتوقيع وAAB | باقٍ | الزوج يحمل com.example وشهادةUAT؛لا AAB متجر رسمي أو مسار تحديث Play مثبت. |
| السياسات والاحتفاظ وصفحة الحذف | باقٍ | يلزم اعتماد النصوص والإفصاح عن السجلات والملفات التي تُحفظ ومددها وتطبيقاتها التشغيلية. |
| Production وأسراره ومراقبته | باقٍ | تكوين مستقل وخطة نشر/تراجع وتنبيهات وحراسة تكلفة وحدود DB/Storage وworker واعتماد المالك. |
| الفيديو3 | باقٍ | قرار تكلفة ومعالجة مستقلة ومراجعة وStorage/FFmpeg وأمان قبل التفعيل. |
| استئناف الرفع11 | باقٍ | OFF وجدول المحاولات غائب؛النسخ والاستعادة بوابة قبل الهجرة والاختبار الكامل. |
| تشغيل الفيديو21 | باقٍ | بعد3:Android native و206Range والتحكم بالوصول والكلفة وقبول المشاهدة. |

## البنود المؤجلة

- #3 و#21: PR111 معزول،لا عاملFFmpegأو تكلفة أو معالجة/تشغيلفيديوأوmigration في هذه الدفعة. يلزم قرار ميزانية وأمن وStorage ومراجعة بشرية وAndroid و206Range.
- #11: PR115 معزول،العلم OFF والجدول غائب؛ النسخ الكامل المشفر والاستعادة المستقلة المثبتة قبل الهجرة. نجاح canary بروتوكول سابق لا يغلق رحلة التطبيق.
- #20:OFFوفق القرار؛ لم تُنفذ مقارنة تشغيل جديدة تبرر كلفة البيانات والذاكرة،فلا تفعيل تلقائي.
- النسخ: المطلوب نسخة قاعدة وتخزين لازمين مشفرة ومفتاح مستقل،واستعادة معزولة مع القيود والعدادات والملفات وRPO/RTO؛ لم تنفذ ولا يحل محلها hashجداول.

## ما يحتاج قرار المالك

### عالية — هوية Android والمتجر

اعتماد Package ID والدومين وربط Play Console وشهادة Play App Signing والرابط الرسمي. أُعدت بوابات الروابط وassetlinks والتحديث، لكن الحزمة الحالية com.example.real_estate_mobile اختبارية. لا مفاتيح خاصة في المحادثة.

### عالية — الإشعارات

تحديد مشروع Firebase الرسمي وإتاحة الإعدادات داخل مدير الأسرار، والموافقة على عامل طابور وتكلفته قبل إنشائه. أُعدت دورة التسجيل والإلغاء والإرسال وإعادة المحاولة؛ يلزم بعدها اختبار هاتفين.

### عالية — OTP والاحتفاظ والحذف

اعتماد مزود OTP والسياسة العامة للاحتفاظ والملفات والسجلات، ثم الدومين وصفحة حذف الإنتاج. يوجد تنفيذ محو واختبارات فشل وتعافٍ، لكن لا سياسة مدد معتمدة ولا ادعاء محو كل سجل مشترك.

### الآن — قبول الهاتف

تنفيذ دليل القبول على النسخة B، واستعمالA→B لاختبار التحديث فقط. جهاز محدود الذاكرة واتصال متقطع، وجهاز Android13+ ثم16 إن أمكن؛ الخريطة والأذونات والمشاركة وقرار الصورة تحتاج حكمًا فعليًا.

### قبل الإطلاق — التشغيل والبنود المؤجلة

إقرار ميزانية الإنتاج ومراقبته، نسخ مشفر واستعادة مستقلة، قياسات109 وحدود السعة، ثم بوابات الفيديو3/21 والرفع11. لم تُنشأ خدمة مدفوعة أو تُنفذ هجرة11 أو يُنشر متجر.

## نسب التقدم وقرار الإطلاق

**اكتمال التجهيز الهندسي للبنود29:25/29=86.2٪**:4معتمدة+20جاهزة للقبول+1OFFمعتمد،والأربعة التي لها خدمة/اعتماد باقٍ بصفر رغم كودها. معيار ثنائي قابل للمراجعة وليس أوزانًا أو عدّ أسطر. على نطاق32مع المؤجل:25/32=78.1٪.

**الجاهزية الفعلية للإطلاق:6/18=33.3٪** على بوابات القائمة أعلاه. تساوي الأوزان فقط للعدّ؛ليست احتمال أمان ولا إذن نشر. أي بوابةP1مفتوحة تمنع GO.

**NO-GO للمتاجر وProduction.** GO محدود لبدء قبول المالك على UAT للبنود المجهزة،مع توثيق موانع8/22/26/31. بعد قبول الهاتف وإغلاق بوابات الإطلاق يُبنىReleaseCandidateبالهوية والتوقيع الرسميين من نفس خط الشيفرة،وموافقة المالك الصريحة قبل أي إنتاج أو متجر أو تكلفة.

عند الإبلاغ عن خلل: البند،البناء،الجهاز/Android،الدور،الثيم/الخط،الشبكة،الوقت والمنطقة،الخطوات،المتوقع والفعلي ولقطة/فيديو بيانات اصطناعية فقط. لا OTP أو مفتاح خاص. نعيد الإنتاج والإصلاح والاختبار وبناء نسخة موحدة جديدة؛لا APKs متفرقة.

