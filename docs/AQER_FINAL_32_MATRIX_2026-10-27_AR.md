# مصفوفة البنود 32 والأدلة — 27 أكتوبر 2026

القرار: **5 مكتملة ومعتمدة، 20 جاهزة لاختبار المالك، 7 جاهزة هندسيًا وموقوفة لمورد/اعتماد خارجي. لا 32/32 تشغيلية.** يشمل الاعتماد قرار 20OFF وفق توجيه المالك. لا هاتف فعلي ولا إشعار FCM حقيقي نُفذا هنا.

المصفوفة الكاملة بكل الحقول القابلة للتدقيق: [JSON](evidence/2026-10-27-final-32-matrix.json). أدناه 32 صفًا للقرار، ثم سجل مستقل لكل بند يضم المتطلبات والحالة السابقة والعمل والملفات و PR/SHA واختبارات Flutter/Laravel/PG/Storage و CI/UAT و Android والمانع والمورد وخطوات ما بعده.

المصدر الموحد بعد PR160: `04b28182645af61c3c7aa11dfbfdaed4c9e86454`. مصدرزوج APK: `3ca26f6ab39b26c0e589299f97285ae0d9b2d1e7`، وشجرةالمصدرالكاملةمتساويةمعالدمج. PR111 و PR115 مختبران لكن غيرمدموجين؛ ميزات 3/11/21 ليستفي APK. الشهاداتوالبصماتفي [تسليم Android](AQER_ANDROID_OWNER_GUIDE_2026-10-27_AR.md).

| # | البند | الحالة السابقة | العمل في الدفعة | الحالة الجديدة | الدليل الأساسي | المانع/المورد | اختبار ما بعده |
|---|---|---|---|---|---|---|---|
| 1 | ملاءمة صور العقار ومراجعتها | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-1)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 2 | تحسين الصور والضغط والمشتقات | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-2)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 3 | رفع ومعالجة الفيديو | مؤجل وموقوف بقرار البوابة؛ PR111 Draft غير مدموج. | مقارنة الفرع القديم مع UAT الحالي وحل التعارضات مع حفظ حمايات الصور والجلسات؛ attempt fencing ومفاتيح مشتقات مستقلة و tombstones وحذف آمن مع كاتب نشط وفشل مزود، bucket فيديو مستقل لا يوسع TUS، metadata من الناتج، وقف playback بالخلفية، Docker و FFmpeg و kill137 ثم تعافٍ. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-3)؛ CI حسب SHA | نسخة DB و Storage حقيقية مشفرة واستعادة مستقلة وموافقة الأمان والتكلفة والهجرة، وعامل فيديو و bucket خاص مستقل. عامل مستقل؛ مبدئيًا 1CPU/2GB بقيمة 25 دولارًا/شهر للقياس، و Storage بحسب الاستخدام. لا شراء الآن. | بعد البوابات: تفعيل canary ورفع 50MiB والتحقق من النوع والملكية و FFmpeg ومراجعة بشرية، و 90s/4K وقتل worker أثناء مراحل الشبكة/DB والتطهير و Range و Android. |
| 4 | العلامة المائية | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-4)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 5 | مشاركة العقارات | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-5)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 6 | منع الإعلانات المكررة | مكتمل ومعتمد | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 1 — مكتمل ومعتمد | [سجل البند](#item-6)؛ CI حسب SHA | لا مانع خاص بالبند ضمن نطاقه المعتمد. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 7 | البلاغات والإشراف | مكتمل ومعتمد | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 1 — مكتمل ومعتمد | [سجل البند](#item-7)؛ CI حسب SHA | لا مانع خاص بالبند ضمن نطاقه المعتمد. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 8 | الإشعارات | مانع خارجي محدد — غير جاهز للاعتماد النهائي | إكمال الاستقبال الأصلي وعزل الحساب/الجلسة/رمز التسجيل والنقر، data-only بلا محتوى خاص، إلغاء قبل الشبكة، عامل مستقل وأسرار/جاهزية ومراقبة وتراجع، و 13 اختبار Android اصطناعيًا. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-8)؛ CI حسب SHA | إضافة سر ملف العميل الحقيقي في Actions، واعتماد إرسال Laravel الخادمي ونافذة عامل، ثم إثبات وصول هاتفين. FCM على Spark بلا رسم مباشر؛ عامل دائم على Render يبدأ 7 دولارات/شهر، أو نافذة اختبار مجانية محدودة بعد توفير الاعتماد والإذن. | إعادة بناء زوج بالملف الحقيقي؛ readiness؛ foreground/background/cold؛ موافقة/إلغاء وتجديدرمز وتبديل حساب ونقر وروابط و 429/5xx وإيقاف الإرسال. |
| 9 | البحث العربي | جاهز وينتظر اختبار المالك على التطبيق | تجميع قراءات overdue لملاك الصفحة مع حفظ السياسة والمبالغ والإشعار؛ قياس 20 مالكًا=9 استعلامات و 5 قراءات مستحقات عند 1 وعند 20، دون نمو N+1. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-9)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 10 | الحظر | مكتمل ومعتمد | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 1 — مكتمل ومعتمد | [سجل البند](#item-10)؛ CI حسب SHA | لا مانع خاص بالبند ضمن نطاقه المعتمد. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 11 | استئناف رفع الوسائط | مؤجل وموقوف بقرار البوابة؛ PR115 Draft غير مدموج. | مقارنة الفرع القديم مع UAT الحالي وحل التعارضات مع حفظ حمايات الصور والجلسات؛ سياج حساب/جلسة حول POST/HEAD/PATCH و finalize، نطاق استئناف بحسب المالك، كتابةذرية ورفض bearer/service_role ومنع السباق واختبارات التراجع. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-11)؛ CI حسب SHA | اعتماد اتصال ووجهة حفظ آمنة واتساق DB/Storage، ونسخة كاملة مشفرة واستعادة مستقلة وفحص صلاحيات وخطة rollback وموافقة الهجرة. يمكن dump و age واستعادة محلية مجانية دون Pro إذا توفرت الصلاحية والسعة؛ ضبط admission للـbucket المشترك وفق حد10MiB المقترح لحفظ وثائق KYC وإثبات الدفع، مع بقاء الإعلان8MiB والتحقق الخادمي؛ راجع بوابة Storage المصححة. | بعد البوابة فقط: الهجرة المحددة؛ RLS/GRANT/FK؛ canary6MiB ثم انقطاع/HEAD/PATCH وتجديد و offset و finalize ملتبس وتبديل حساب و cleanup و Android بعد قتل التطبيق. |
| 12 | الصور المتكيفة | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-12)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 13 | التحميل الكسول | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-13)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 14 | التخزين المؤقت | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. حماية بدءالخروج و epoch الحالية تمنع بقاء ردود حساب قديم؛ مسار TUS الجديد محفوظ في PR115 فقط. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-14)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 15 | التعافي من أخطاء الشبكة | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-15)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 16 | حالات التحميل والفراغ والخطأ وإعادة المحاولة | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-16)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 17 | تجميع علامات الخريطة | جاهز وينتظر اختبار المالك على التطبيق | تجميع قراءات overdue لملاك الصفحة مع حفظ السياسة والمبالغ والإشعار؛ قياس 20 مالكًا=9 استعلامات و 5 قراءات مستحقات عند 1 وعند 20، دون نمو N+1. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-17)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 18 | الصفحات والتحميل التدريجي | جاهز وينتظر اختبار المالك على التطبيق | تجميع قراءات overdue لملاك الصفحة مع حفظ السياسة والمبالغ والإشعار؛ قياس 20 مالكًا=9 استعلامات و 5 قراءات مستحقات عند 1 وعند 20، دون نمو N+1. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-18)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 19 | Debounce وإلغاء الطلبات | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. حماية بدءالخروج و epoch الحالية تمنع بقاء ردود حساب قديم؛ مسار TUS الجديد محفوظ في PR115 فقط. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-19)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 20 | Prefetch المشروط | OFF معتمد مشروط | اعتماد قرار OFF وفق توجيه المالك الحالي؛ لا تفعيل ولا حاجة لاختراع تجربة تشغيل ناجحة. | 1 — مكتمل ومعتمد | [سجل البند](#item-20)؛ CI حسب SHA | لا مانع خاص بالبند ضمن نطاقه المعتمد. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 21 | تشغيل الفيديو على Android | مؤجل وموقوف بقرار البوابة؛ PR111 Draft غير مدموج. | مقارنة الفرع القديم مع UAT الحالي وحل التعارضات مع حفظ حمايات الصور والجلسات؛ attempt fencing ومفاتيح مشتقات مستقلة و tombstones وحذف آمن مع كاتب نشط وفشل مزود، bucket فيديو مستقل لا يوسع TUS، metadata من الناتج، وقف playback بالخلفية، Docker و FFmpeg و kill137 ثم تعافٍ. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-21)؛ CI حسب SHA | تفعيل 3 الآمن وعامل و Storage ومراجعة بشرية، ثم تشغيل Android فعلي و Range على المورد المعتمد. العامل نفسه المطلوب للبند 3؛ لا مورد معالجة إضافي تلقائيًا. رسوم الفيديو تأتي من worker/storage/egress. | جاهزية مشتق H264/AAC و poster، 206/416 و seek و play/pause/lifecycle/rotation/انقطاع، حساب آخر ورفض غير مراجع، ومراقبة bytes/RSS. |
| 22 | Deep Links و App Links | مانع خارجي محدد — غير جاهز للاعتماد النهائي | تثبيت flavor وهوية UAT الجديدة وحماية Production؛ زوج 1358/1359 بنفس الشهادة، ومحاكي API36 وحفظ ملفي fixture؛ مراجعة الروابط/الأذونات والتحديث دون ادعاء Play أو هاتف. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-22)؛ CI حسب SHA | اسم HTTPS رسمي وهوية وتوقيع معتمدان، ونشر assetlinks والتحقق الحقيقي من Android. قرار الدومين و DNS/TLS؛ السعر حسب الاسم/TLD والتجديد، لم يُحجز شيء. بصمة Play لا تُستبدل ببصمة UAT المؤقتة. | assetlinks صالح للمضيف/الحزمة/الشهادة؛ adb verify-app-links وفتح منخارج التطبيق مغلقًا/مفتوحًا، والعودة بعد login ورفض الروابط الخبيثة/المضيف/المنفذ. |
| 23 | العقارات المشاهدة مؤخرًا | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-23)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 24 | حفظ حالة الاستكشاف والعودة إليها | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-24)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 25 | تجربة عدم وجود نتائج | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-25)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 26 | التحقق من تحديث التطبيق | مانع خارجي محدد — غير جاهز للاعتماد النهائي | تثبيت flavor وهوية UAT الجديدة وحماية Production؛ زوج 1358/1359 بنفس الشهادة، ومحاكي API36 وحفظ ملفي fixture؛ مراجعة الروابط/الأذونات والتحديث دون ادعاء Play أو هاتف. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-26)؛ CI حسب SHA | مفتاح UAT ثابت لسلاسل البناء المستقبلية، و Production package و PlayAppSigning ورابط المتجر الرسمي واختبار تحديث Play. إنشاء/حفظ مفتاح Android لايتطلب اشتراكشهادة؛ PlayConsole25 دولارًا مرةواحدة، ولا تسجيل/نشر الآن. | تحقق build/version وعدم downgrade ومساري optional/mandatory وروابط allowlist؛ ثم A→B عبر PlayInternal مع حفظ الجلسة/البيانات والهجرات المطلوبة. |
| 27 | الصلاحيات عند الحاجة | جاهز وينتظر اختبار المالك على التطبيق | تثبيت flavor وهوية UAT الجديدة وحماية Production؛ زوج 1358/1359 بنفس الشهادة، ومحاكي API36 وحفظ ملفي fixture؛ مراجعة الروابط/الأذونات والتحديث دون ادعاء Play أو هاتف. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-27)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 28 | خصوصية EXIF | مكتمل ومعتمد | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 1 — مكتمل ومعتمد | [سجل البند](#item-28)؛ CI حسب SHA | لا مانع خاص بالبند ضمن نطاقه المعتمد. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 29 | إدارة صور الإعلانات | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-29)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 30 | المسودات واستعادتها | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. حماية بدءالخروج و epoch الحالية تمنع بقاء ردود حساب قديم؛ مسار TUS الجديد محفوظ في PR115 فقط. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-30)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |
| 31 | حذف الحساب | مانع خارجي محدد — غير جاهز للاعتماد النهائي | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 3 — جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي | [سجل البند](#item-31)؛ CI حسب SHA | اعتماد سياسة حذف/احتفاظ للبيانات والوسائط المؤرشفة وحقوق الوصول، ومزود OTP لليمن وصفحة حذف Production وقبول الهاتف. قرار سياسة بلا مدة أو مسوغ قانوني مختلق؛ OTP حسب المزود والقناة. مرجع Twilio0.05 دولار/تحقق+القناة، ليس عرض اليمن. | expired/wrong/reusedOTP و throttle؛ جلسةقديمة؛ storagefailure/retry وسباقاتالحذف والمراجعالمشتركة؛ تدقيق البيان المنشور وصفحةالويب. |
| 32 | الثيم والتناسق والاتجاه | جاهز وينتظر اختبار المالك على التطبيق | مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. | 2 — جاهز وينتظر اختبار المالك على Android | [سجل البند](#item-32)؛ CI حسب SHA | قبول المالك على Android فقط وفق الرحلة أدناه. لا مورد إضافي يمنع تجربة المالك لهذا البند. | لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند. |

## طريقة الحساب

- **engineering_implementation_unified: 29/32 = 90.625%**. 29 بندًا لها التنفيذ الآمن في الفرع الموحد.3/11/21 مجهزة ومختبرة في فروع معزولة ولا تحسب تنفيذًا مدموجًا أو تشغيليًا.
- **owner_test_readiness: 25/32 = 78.125%**. 5 معتمدة+20 قابلة لاختبار المالك؛ الـ 20 المنتظرة وحدها 62.5%.
- **activation_preparedness: 32/32 = 100.0%**. مقبول أو جاهز للهاتف أو له كود معزول مختبر وخطة تفعيل/تراجع ومانع خارجي محدد؛ لا يعني توفر الموارد.
- **operational_item_acceptance: 5/32 = 15.625%**. نسبة اعتماد البنود تشغيليًا وفق نطاقها وقرار OFF20؛ ليست تصريح متجر أو احتمال نجاح إطلاق.

هذه أوزان متساوية للبنود لغرض التتبع، ولا تعكس أهمية كل ميزة أو احتمال نجاح تجاري. القرار المنطقي للإطلاق NO-GO حتى قبول الهاتف والموارد والأداء والأمان والسياسات والتوقيع والمتجر؛ لا يلغي 100%تحضير هذه البوابات.

<a id="item-1"></a>

## 1 — ملاءمة صور العقار ومراجعتها

**المتطلبات:** لا يُنشر الإعلان قبل مراجعة بشرية لكل صوره الحالية، مع ربط القرار ببصمة تمنع استخدام موافقة لصورة استُبدلت.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Http/Controllers/Api/ListingReviewController.php`
- `mobile_app/lib/features/reviews/presentation/listing_review_screen.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#114](https://github.com/JJalal1/real-estate-uat-backend/pull/114) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#143](https://github.com/JJalal1/real-estate-uat-backend/pull/143) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/Stage9ListingReviewApiTest.php", "backend-api-runtime/tests/Feature/Wave2MediaTrustTest.php", "backend-api-runtime/app/Console/Commands/UatRoleJourneys.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "رحلات UAT للمراجعة وبصمة الصورة ورفض الوصول؛ preflight الجديد يثبت أن المراجع يستطيع فتح إعلان القبول الحالي وصورتيه. اختبار الشاشة الداخلية وإبطال الأدلة المتأخرة ضمن PR158.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP→Laravel→PostgreSQL→Storage؛ يمنع النشر قبل مراجعة الصورة الحالية.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** رحلات UAT للمراجعة وبصمة الصورة ورفض الوصول؛ preflight الجديد يثبت أن المراجع يستطيع فتح إعلان القبول الحالي وصورتيه. اختبار الشاشة الداخلية وإبطال الأدلة المتأخرة ضمن PR158.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** الوسيط ثم المراجع

**الخطوات:** افتح إعلان «اختبار المالك — مراجعة الصور»؛ أرسل للمراجع/افتح الوارد واستلم المهمة؛ صنّف صورة المكتب مناسبة والنمط الملون غير مناسب، وأعد الإعلان بسبب واضح. بدّل الصورة من حساب الوسيط وأعد الإرسال، ثم راجع النسخة الحالية.

**المتوقع:** الصور غير المراجعة أو غير المناسبة تمنع النشر؛ الاستبدال يلغي القرار القديم ويحتاج مراجعة جديدة.

**السلبي:** جرّب اعتماد الإعلان قبل مراجعة كل الصور، وفتح المهمة من حساب دعم آخر.

<a id="item-2"></a>

## 2 — تحسين الصور والضغط والمشتقات

**المتطلبات:** أصل خاص ومشتقات عرض JPEG مضبوطة الحجم والجودة، مع رفض الملفات غير الصالحة وعدم تكرار النقل بلا حاجة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/ListingImageService.php`
- `backend-api-runtime/app/Services/CloudAssetStorageService.php`
- `backend-api-runtime/app/Services/ListingImageEncodingGate.php`
- `backend-api-runtime/tests/Support/probe_large_images.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#119](https://github.com/JJalal1/real-estate-uat-backend/pull/119) [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#150](https://github.com/JJalal1/real-estate-uat-backend/pull/150) [#155](https://github.com/JJalal1/real-estate-uat-backend/pull/155)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/AdaptiveImageQualityTest.php", "backend-api-runtime/tests/Feature/CloudDeleteLifecycleTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "قياس Docker حقيقي: 24MP و 512MiB و 1CPU؛ فشل OOM baseline عند التزامن 3، ثم 6/6 عمليات ناجحة بالتزامن 1/2/3 دون OOM مع backpressure503. أقصى cgroup نحو 357MiB؛ لا يعادل ذاكرة الهاتف.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "رفع/قراءة/حذف فعلي لصور اصطناعية في bucket خاص؛ قياس مشتقات عبر HTTP.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** قياس Docker حقيقي: 24MP و 512MiB و 1CPU؛ فشل OOM baseline عند التزامن 3، ثم 6/6 عمليات ناجحة بالتزامن 1/2/3 دون OOM مع backpressure503. أقصى cgroup نحو 357MiB؛ لا يعادل ذاكرة الهاتف.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** الوسيط

**الخطوات:** أضف صور الاختبار 24MP إلى مسودة فقط؛ جرّب صورة عادية ثم مدوّرة، ثم عدة صور. انتقل بين المعرض والبطاقة والتفاصيل، وأعد المحاولة إن ظهرت رسالة انشغال.

**المتوقع:** عرض بالاتجاه الصحيح، ونسخ عرض أصغر؛ نجاح واضح دون توقف التطبيق؛ 503 المحتمل مؤقت ولا يُحسب حفظًا ناجحًا.

**السلبي:** صورة تالفة، ملف أكبر من 8MiB، انقطاع أثناء الرفع؛ يجب ألا يتكرر الحفظ أو تضيع المسودة. قياس ذاكرة الهاتف نفسه لا يستنتج من قياس الخادم.

<a id="item-3"></a>

## 3 — رفع ومعالجة الفيديو

**المتطلبات:** رفع خاص محدود الحجم والنوع والملكية، FFmpeg بعامل مستقل ومشتقات و poster ومراجعة بشرية وإعادة محاولة وتنظيف بلا تسريب.

**السابق:** مؤجل وموقوف بقرار البوابة؛ PR111 Draft غير مدموج.

**المنجز الآن:** مقارنة الفرع القديم مع UAT الحالي وحل التعارضات مع حفظ حمايات الصور والجلسات؛ attempt fencing ومفاتيح مشتقات مستقلة و tombstones وحذف آمن مع كاتب نشط وفشل مزود، bucket فيديو مستقل لا يوسع TUS، metadata من الناتج، وقف playback بالخلفية، Docker و FFmpeg و kill137 ثم تعافٍ.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. اجتياز التشغيل المقاس وقبول بوابات الدمج/البيانات ينقل إلى 2؛ قبول المالك والرحلة الكاملة ينقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Jobs/ProcessListingVideo.php`
- `backend-api-runtime/app/Models/ListingVideo.php`
- `backend-api-runtime/app/Http/Controllers/Api/ListingVideoController.php`
- `backend-api-runtime/app/Http/Controllers/Api/PropertyController.php`
- `backend-api-runtime/app/Services/CloudAssetStorageService.php`
- `backend-api-runtime/app/Services/ListingVideoTranscoder.php`
- `backend-api-runtime/app/Services/AccountErasureService.php`
- `backend-api-runtime/database/migrations/2026_10_23_000100_create_listing_videos_table.php`
- `backend-api-runtime/Dockerfile.video-worker`
- `mobile_app/lib/features/properties/presentation/property_video_section.dart`
- `scripts/probe_video_worker_container.py`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Jobs/ProcessListingVideo.php`
- `backend-api-runtime/app/Models/ListingVideo.php`
- `backend-api-runtime/app/Http/Controllers/Api/ListingVideoController.php`
- `backend-api-runtime/app/Http/Controllers/Api/PropertyController.php`
- `backend-api-runtime/app/Services/CloudAssetStorageService.php`
- `backend-api-runtime/app/Services/ListingVideoTranscoder.php`
- `backend-api-runtime/app/Services/AccountErasureService.php`
- `backend-api-runtime/database/migrations/2026_10_23_000100_create_listing_videos_table.php`
- `backend-api-runtime/Dockerfile.video-worker`
- `mobile_app/lib/features/properties/presentation/property_video_section.dart`
- `scripts/probe_video_worker_container.py`

**PRs:** [#111](https://github.com/JJalal1/real-estate-uat-backend/pull/111)

**SHAs:** tested_feature_head=`d29d4c09e8a4e5efc18f3facdd6ce9397b3cd32e`؛ current_integrated_engineering_base=`ca3ced8f60eed067ce1406b6661bcc583274199f`

**Flutter:** {"result": "PASS on feature head; Android handset not tested", "files": ["mobile_app/test/property_video_section_test.dart", "mobile_app/test/stage9_review_models_test.dart"]}

**Laravel:** {"result": "PASS on feature head", "files": ["backend-api-runtime/tests/Feature/ListingVideoApiTest.php", "backend-api-runtime/tests/Feature/ListingVideoFullCycleTest.php", "backend-api-runtime/tests/Feature/ListingVideoTranscoderTest.php", "backend-api-runtime/tests/Feature/ListingVideoStreamTest.php", "backend-api-runtime/tests/Feature/VideoCloudStorageProtocolTest.php"]}

**PostgreSQL و Storage:** {"result": "Disposable PostgreSQL PASS; source/permission/storage protocol regressions PASS; no live DDL or feature activation", "files": ["backend-api-runtime/tests/Postgres/ListingVideoPostgresTest.php"]}

**CI:** PR111:26success/0failure/1fallbackskip؛ 50 اختبار قبول/Storage و 299assertions، 7Flutter موجهة وبناء Android، تحويل 2s→720p≈702–707ms و RSSchild≈181MiB، و SIGKILL137 لحاوية FFmpeg ثمتحويلناجح؛ ليس قتل queuelease حقيقيًا.

**UAT:** لم ينشر أو يفعل هذا الفرع على UAT؛ الجدول غائب والأعلام مغلقة. أدلة بروتوكول التخزين التاريخية لا تحل محل البوابات.

**Android:** الاختبارات والبناء الآلي ناجحان للفرع؛ الميزة OFF فيحزمة 1359 الموحدة؛ لا اختبار هاتف لهذه الميزة.

**دليل القرار:** PR111:26success/0failure/1fallbackskip؛ 50 اختبار قبول/Storage و 299assertions، 7Flutter موجهة وبناء Android، تحويل 2s→720p≈702–707ms و RSSchild≈181MiB، و SIGKILL137 لحاوية FFmpeg ثمتحويلناجح؛ ليس قتل queuelease حقيقيًا.؛ docs/VIDEO_CURRENT_BASE_REVIEW_2026-10-26_AR.md؛ docs/AQER_BACKUP_RESTORE_ACTIVATION_2026-10-27_AR.md

**المانع النهائي:** نسخة DB و Storage حقيقية مشفرة واستعادة مستقلة وموافقة الأمان والتكلفة والهجرة، وعامل فيديو و bucket خاص مستقل.

**المورد والتكلفة/التفعيل:** عامل مستقل؛ مبدئيًا 1CPU/2GB بقيمة 25 دولارًا/شهر للقياس، و Storage بحسب الاستخدام. لا شراء الآن.

**اختبار ما بعد توفيره:** بعد البوابات: تفعيل canary ورفع 50MiB والتحقق من النوع والملكية و FFmpeg ومراجعة بشرية، و 90s/4K وقتل worker أثناء مراحل الشبكة/DB والتطهير و Range و Android.

**اختبار المالك — الدور:** مالك مسودة ثم مراجع ثم باحث

**الخطوات:** تؤجل الرحلة حتى اجتياز البوابة، ثم اتبع خطة الاختبار بعد توفير المورد أعلاه. لا تفعّل علمًا لتجاوز هذه الخطوة.

**المتوقع:** نقل/عرض/تعافٍ آمن مع ثبات الملكية والمراجعة والتطهير وإيصال فشل حقيقي، دون تسريب أو نجاح وهمي.

**السلبي:** حساب آخر، ملف تالف/كبير، انقطاع، إعادةتسليم/ضغطمتكرر، قتل العملية، فشل التخزين والتنظيف، وتغير الحالة أثناء التنفيذ.

<a id="item-4"></a>

## 4 — العلامة المائية

**المتطلبات:** استخدام الأصل المعتمد وبصمته على مشتقات العرض وتنظيف مشتقات ما قبل التفعيل/التراجع دون حذف ملف مستخدم.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/ListingWatermarkService.php`
- `backend-api-runtime/app/Services/ListingImageService.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/AdaptiveImageQualityTest.php", "backend-api-runtime/tests/Feature/CloudDeleteLifecycleTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "مشتقات UAT v2-wm وعينة اصطناعية مفحوصة بصريًا؛ watermark_active=true ورفض الأصل 422 و 304. العلامة كانت ON ولم نفعلها من جديد.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "تنظيف الأصل ومشتقات الصورة المزالة مثبت حيًا؛ لم يُفعّل علم علامة جديد.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** مشتقات UAT v2-wm وعينة اصطناعية مفحوصة بصريًا؛ watermark_active=true ورفض الأصل 422 و 304. العلامة كانت ON ولم نفعلها من جديد.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** افتح العقارات 60 و 61 و 62 ثم الصورة المكبرة، وقارن عينة العلامة المرفقة.

**المتوقع:** تظهر علامة عقار المعتمدة دون حجب التفاصيل الأساسية؛ الأصل الخاص غير قابل للوصول العام.

**السلبي:** راجع العلامة في الوضعين الفاتح والداكن وعلى شبكة ضعيفة؛ لا تغير إعداد التشغيل.

<a id="item-5"></a>

## 5 — مشاركة العقارات

**المتطلبات:** مشاركة أصلية تؤدي إلى العقار الصحيح، مع رابط آمن واحترام حالة الإعلان.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/platform/platform_share.dart`
- `mobile_app/lib/router/app_deep_links.dart`
- `mobile_app/android/app/src/main/AndroidManifest.xml`
- `mobile_app/test/owner_share_release_test.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#123](https://github.com/JJalal1/real-estate-uat-backend/pull/123) [#133](https://github.com/JJalal1/real-estate-uat-backend/pull/133) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/phase3_deep_links_test.dart", "mobile_app/test/deep_link_origin_guard_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "MethodChannel42→84 عند إعادة استخدام الواجهة، ومنع مشاركة المسودة؛ صفحة مشاركة UAT حقيقية للعقارات 60–62. فتح التطبيقات الخارجية على الهاتف باقٍ.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "عقد المسار وحالة العقار محفوظان؛ فحوص Flutter و APK.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** MethodChannel42→84 عند إعادة استخدام الواجهة، ومنع مشاركة المسودة؛ صفحة مشاركة UAT حقيقية للعقارات 60–62. فتح التطبيقات الخارجية على الهاتف باقٍ.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** افتح العقار 60 ثم اضغط مشاركة وأرسله إلى تطبيق تختاره؛ كرر للعقار 61؛ افتح الرابط من التطبيق الخارجي.

**المتوقع:** المحتوى والعنوان والرابط يخصان العقار الحالي؛ صفحة UAT الخارجية قابلة للفتح.

**السلبي:** لا مشاركة لمسودة؛ جرّب عقارًا لم يعد متاحًا. وصول رابط HTTPS مباشرة إلى التطبيق يحتاج App Links الرسمية في 22.

<a id="item-6"></a>

## 6 — منع الإعلانات المكررة

**المتطلبات:** الهوية الفيزيائية للعقار واحدة؛ إعادة الطلب أو اختلاف المعلن لا يسمحان بنشر تمثيل مكرر.

**السابق:** مكتمل ومعتمد

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** مكتمل ومعتمد. اجتاز شروط الاعتماد ضمن النطاق.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/PropertyIdentityService.php`
- `backend-api-runtime/app/Http/Controllers/Api/PropertyController.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/PropertyIdentityV2Test.php", "backend-api-runtime/app/Console/Commands/UatRoleJourneys.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "اختبارات HTTP حقيقية للحالة duplicate_same_physical_asset ورفض التكرار الفيزيائي؛ قيود PostgreSQL والتراجع نجحت. لم تخفف القاعدة أو assertions.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP حي: إعادة إنشاء بعد استجابة مفقودة 409؛ معلنان للعقار الفيزيائي نفسه؛ رفض النشر المكرر مع سبب محدد.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** اختبارات HTTP حقيقية للحالة duplicate_same_physical_asset ورفض التكرار الفيزيائي؛ قيود PostgreSQL والتراجع نجحت. لم تخفف القاعدة أو assertions.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** لا مانع خاص بالبند ضمن نطاقه المعتمد.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** الوسيط

**الخطوات:** فحص تراجع اختياري: حاول إنشاء إعلان جديد للهوية الفيزيائية نفسها دون تغيير الدور أو الوحدة.

**المتوقع:** يمنع النظام تكرار العقار أو تمثيله من معلن آخر؛ تغيير الغرض لا يجيز إعلانًا مكررًا.

**السلبي:** لا تغيّر الاختبارات أو أرقام الهوية للتحايل على الرفض.

<a id="item-7"></a>

## 7 — البلاغات والإشراف

**المتطلبات:** بلاغ عقار/محادثة بإيصال مستقر، queue/claim وصلاحيات للمراجعة والإغلاق؛ فتح محتوى خاص بإذن وسجل تدقيق.

**السابق:** مكتمل ومعتمد

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** مكتمل ومعتمد. اجتاز شروط الاعتماد ضمن النطاق.

**الملفات المراجعة:**

- `backend-api-runtime/app/Http/Controllers/Api/SupportController.php`
- `backend-api-runtime/app/Http/Controllers/Api/MessagingController.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#143](https://github.com/JJalal1/real-estate-uat-backend/pull/143)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/Wave2AccountSafetyTest.php", "backend-api-runtime/tests/Feature/Stage11MessagingNotificationsApiTest.php", "backend-api-runtime/app/Console/Commands/UatRoleJourneys.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "رحلات إنشاء/تكرار/استلام/حل البلاغ ورفض القراءة الخاصة دون صلاحية وسياق بلاغ؛ اختبارات الملكية وعزل الحسابات قائمة وناجحة.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP حي مع PostgreSQL: إيصال/claim/resolve ورفض 403/404/409 وتدقيق الوصول الخاص؛ لا صلاحيات موسعة.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** رحلات إنشاء/تكرار/استلام/حل البلاغ ورفض القراءة الخاصة دون صلاحية وسياق بلاغ؛ اختبارات الملكية وعزل الحسابات قائمة وناجحة.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** لا مانع خاص بالبند ضمن نطاقه المعتمد.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم ثم الدعم

**الخطوات:** بلّغ عن إعلان أو محادثة اصطناعية، ثم افتح الوارد بالدعم واستلم البلاغ وسجل القرار.

**المتوقع:** بلاغ واحد قابل للتتبع وملكية مهمة واضحة؛ فتح الرسائل الخاصة يحتاج صلاحية مستقلة ويسجل.

**السلبي:** حاول فتح محتوى خاص من حساب لا يملك الصلاحية؛ يجب أن يرفض. لا تفحص محادثات بشرية.

<a id="item-8"></a>

## 8 — الإشعارات

**المتطلبات:** تسجيل جهاز بموافقة سليمة وتفضيلات/إلغاء، و delivery/retry عبر مزود و queue معتمدين، مع عزل الحساب.

**السابق:** مانع خارجي محدد — غير جاهز للاعتماد النهائي

**المنجز الآن:** إكمال الاستقبال الأصلي وعزل الحساب/الجلسة/رمز التسجيل والنقر، data-only بلا محتوى خاص، إلغاء قبل الشبكة، عامل مستقل وأسرار/جاهزية ومراقبة وتراجع، و 13 اختبار Android اصطناعيًا.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. لا يسجل جاهزًا لهاتف المالك للإرسال حتى يعمل الربط الحقيقي؛ بعد إثبات التشغيل يصبح 2، ثم قبول المالك 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/messages/data/push_registration_repository.dart`
- `backend-api-runtime/app/Http/Controllers/Api/PushDeviceController.php`
- `backend-api-runtime/tests/Feature/PushDeliveryLifecycleTest.php`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Services/FcmPushSender.php`
- `backend-api-runtime/app/Jobs/SendUserPushNotification.php`
- `backend-api-runtime/app/Console/Commands/PushReadiness.php`
- `backend-api-runtime/config/push.php`
- `backend-api-runtime/Dockerfile.queue-worker`
- `mobile_app/lib/features/messages/data/push_registration_repository.dart`
- `mobile_app/lib/features/account/data/auth_controller.dart`
- `mobile_app/lib/core/push/push_launch_coordinator.dart`
- `mobile_app/android/app/src/main/kotlin/com/example/real_estate_mobile/PushSessionState.kt`
- `mobile_app/android/app/src/main/kotlin/com/example/real_estate_mobile/PushBridge.kt`
- `mobile_app/android/app/src/main/kotlin/com/example/real_estate_mobile/AqerMessagingService.kt`
- `mobile_app/android/app/src/main/kotlin/com/example/real_estate_mobile/AqerApplication.kt`
- `scripts/probe_android_push_isolation.py`

**PRs:** [#132](https://github.com/JJalal1/real-estate-uat-backend/pull/132) [#139](https://github.com/JJalal1/real-estate-uat-backend/pull/139) [#151](https://github.com/JJalal1/real-estate-uat-backend/pull/151) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/push_registration_guard_test.dart", "mobile_app/test/push_registration_guard_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/PushLaunchPrepTest.php", "backend-api-runtime/tests/Postgres/NotificationPreferencePostgresTest.php", "backend-api-runtime/tests/Feature/PushDeliveryLifecycleTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "10 اختبارات دورة إرسال: إعادة فحص المستخدم/الموافقة/الجهاز، UNREGISTERED دقيق، 429/5xx و Retry-After واستنفاد المحاولات. لا FCM هاتف فعليًا؛ devices=0 عند الفحص.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "عقد التسجيل والتفضيلات ورفض المدخلات مثبت CI؛ إشعارات داخل التطبيق مثبتة في الرحلات.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** 10 اختبارات دورة إرسال: إعادة فحص المستخدم/الموافقة/الجهاز، UNREGISTERED دقيق، 429/5xx و Retry-After واستنفاد المحاولات. لا FCM هاتف فعليًا؛ devices=0 عند الفحص.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** إضافة سر ملف العميل الحقيقي في Actions، واعتماد إرسال Laravel الخادمي ونافذة عامل، ثم إثبات وصول هاتفين.

**المورد والتكلفة/التفعيل:** FCM على Spark بلا رسم مباشر؛ عامل دائم على Render يبدأ 7 دولارات/شهر، أو نافذة اختبار مجانية محدودة بعد توفير الاعتماد والإذن.

**اختبار ما بعد توفيره:** إعادة بناء زوج بالملف الحقيقي؛ readiness؛ foreground/background/cold؛ موافقة/إلغاء وتجديدرمز وتبديل حساب ونقر وروابط و 429/5xx وإيقاف الإرسال.

**اختبار المالك — الدور:** حسابان وهاتفان عند تفعيل الخدمة الرسمية

**الخطوات:** يمكن الآن اختبار قائمة الإشعارات والتفضيلات. بعد ربط Firebase والعامل، امنح الإذن، أنشئ حدثًا للحساب الثاني، واختبر المقدمة والخلفية ثم تسجيل الخروج.

**المتوقع:** القائمة الداخلية تحفظ الحدث؛ التسليم للهاتف يُثبت منفصلًا، مع منع الإرسال بعد سحب الموافقة أو تعطيل الحساب.

**السلبي:** 429 و 5xx وإعادة المحاولة مثبتة بمحاكاة المزود؛ FCM معطل حاليًا ولا يُتوقع Push حقيقي في هذه النسخة.

<a id="item-9"></a>

## 9 — البحث العربي

**المتطلبات:** تطبيع وصلة فلاتر وترتيب وصفحات موثوق، وتمييز الصفر عن فشل الشبكة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** تجميع قراءات overdue لملاك الصفحة مع حفظ السياسة والمبالغ والإشعار؛ قياس 20 مالكًا=9 استعلامات و 5 قراءات مستحقات عند 1 وعند 20، دون نمو N+1.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Http/Controllers/Api/PropertyController.php`
- `mobile_app/lib/features/discovery/data/smart_search_session.dart`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Http/Controllers/Api/FinancialPropertyController.php`
- `backend-api-runtime/app/Services/PropertyFinancialService.php`
- `backend-api-runtime/app/Services/CompletePropertyFinancialService.php`

**PRs:** [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#137](https://github.com/JJalal1/real-estate-uat-backend/pull/137) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/search_query_wave_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/DiscoverySearchQualityTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "بحث UAT عربي وإب/اب والفلاتر والفراغ؛ PostgreSQL17 و PostGIS؛ حمل 10k اصطناعي للبحث. لا ادعاء قياس شامل لكل لهجة أو خدمة صوت خارجية.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "بحث HTTP/PG و fixture اصطناعي دقيق؛ عينة أداء محددة لا شهادة شاملة لكل لهجة أو مزود AI.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** بحث UAT عربي وإب/اب والفلاتر والفراغ؛ PostgreSQL17 و PostGIS؛ حمل 10k اصطناعي للبحث. لا ادعاء قياس شامل لكل لهجة أو خدمة صوت خارجية.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** ابحث عن «إب» ثم «اب»، وبدّل المحافظة والنوع والغرض والترتيب، ثم عد إلى النتائج.

**المتوقع:** نتائج متسقة مع التطبيع والفلاتر، مع إظهار المعايير الحالية.

**السلبي:** بحث لا يطابق شيئًا ثم انقطاع الشبكة: الفراغ يختلف عن الخطأ؛ الصوت تابع لإذن/خدمة مستقلة.

<a id="item-10"></a>

## 10 — الحظر

**المتطلبات:** الحظر الشخصي يمنع الرسائل والاتصال الجديد من الاتجاهين دون إتلاف التاريخ؛ فك الحظر لا يغير قرار الطرف الآخر.

**السابق:** مكتمل ومعتمد

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** مكتمل ومعتمد. اجتاز شروط الاعتماد ضمن النطاق.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/UserMessagingBlockService.php`
- `backend-api-runtime/app/Http/Controllers/Api/AccountSafetyController.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#143](https://github.com/JJalal1/real-estate-uat-backend/pull/143)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Postgres/MessagingBlockPostgresTest.php", "backend-api-runtime/tests/Feature/Wave2AccountSafetyTest.php", "backend-api-runtime/app/Console/Commands/UatRoleJourneys.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "اختبارات حظر متبادل وطرق بدء المحادثة والاتصال ورفض التجاوز؛ قفل PostgreSQL وتزامن قائم. يحتفظ الحظر بتاريخ المحادثات.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP/PG وحالات رفض واضحة؛ لا تحويل الحظر الشخصي إلى ban إداري.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** اختبارات حظر متبادل وطرق بدء المحادثة والاتصال ورفض التجاوز؛ قفل PostgreSQL وتزامن قائم. يحتفظ الحظر بتاريخ المحادثات.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** لا مانع خاص بالبند ضمن نطاقه المعتمد.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم وحساب آخر

**الخطوات:** فحص تراجع اختياري: افتح محادثة اصطناعية واحظر الطرف الآخر، وحاول بدء محادثة/رسالة من الطرفين ثم ألغِ الحظر.

**المتوقع:** يُطبق الحظر في الخادم؛ تبقى المحادثات السابقة ولا تسمح معرّفات بديلة بتجاوزه.

**السلبي:** اختبر حظر الطرفين وإلغاء حظر طرف واحد؛ لا يكفي ذلك إذا بقي حظر من الطرف الآخر.

<a id="item-11"></a>

## 11 — استئناف رفع الوسائط

**المتطلبات:** استئناف نقل حقيقي من offset بعد انقطاع/قتل، بلا إعادة الأجزاء المؤكدة أو تخطي الملكية والـ revision؛ هجرة بعد بوابة نسخ واستعادة فعلية.

**السابق:** مؤجل وموقوف بقرار البوابة؛ PR115 Draft غير مدموج.

**المنجز الآن:** مقارنة الفرع القديم مع UAT الحالي وحل التعارضات مع حفظ حمايات الصور والجلسات؛ سياج حساب/جلسة حول POST/HEAD/PATCH و finalize، نطاق استئناف بحسب المالك، كتابةذرية ورفض bearer/service_role ومنع السباق واختبارات التراجع.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. اختبارات التشغيل والهجرة المعتمدة مع مواردها تنقل إلى 2؛ قبول المالك لاستئناف حقيقي على Android ينقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/ListingImageUploadIntentService.php`
- `backend-api-runtime/app/Models/ListingImageUploadIntent.php`
- `backend-api-runtime/database/migrations/2026_10_23_220000_create_listing_image_upload_intents.php`
- `mobile_app/lib/features/properties/data/private_tus_image_uploader.dart`
- `mobile_app/lib/features/properties/data/listing_account_draft_repository.dart`
- `mobile_app/test/private_tus_image_uploader_test.dart`
- `mobile_app/test/listing_resume_session_test.dart`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Services/ListingImageUploadIntentService.php`
- `backend-api-runtime/app/Models/ListingImageUploadIntent.php`
- `backend-api-runtime/database/migrations/2026_10_23_220000_create_listing_image_upload_intents.php`
- `mobile_app/lib/features/properties/data/private_tus_image_uploader.dart`
- `mobile_app/lib/features/properties/data/listing_account_draft_repository.dart`
- `mobile_app/test/private_tus_image_uploader_test.dart`
- `mobile_app/test/listing_resume_session_test.dart`

**PRs:** [#115](https://github.com/JJalal1/real-estate-uat-backend/pull/115)

**SHAs:** tested_feature_head=`9f5e16b14f565e708afa3597d06e2c03aa1d5561`؛ current_integrated_engineering_base=`ca3ced8f60eed067ce1406b6661bcc583274199f`

**Flutter:** {"result": "PASS on feature head; Android handset not tested", "files": ["mobile_app/test/private_tus_image_uploader_test.dart", "mobile_app/test/listing_resume_session_test.dart", "mobile_app/test/user_work_media_test.dart"]}

**Laravel:** {"result": "PASS on feature head", "files": ["backend-api-runtime/tests/Unit/PrivateResumableImageTicketTest.php", "backend-api-runtime/tests/Unit/ResumableImageFinalizationTest.php", "backend-api-runtime/tests/Feature/UserWorkMediaTest.php"]}

**PostgreSQL و Storage:** {"result": "Disposable PostgreSQL PASS; source/permission/storage protocol regressions PASS; no live DDL or feature activation", "files": ["backend-api-runtime/tests/Postgres/ListingImageUploadIntentPostgresTest.php"]}

**CI:** PR115:25success/0failure/1fallbackskip؛ اختبارات تذاكر/TUS/PG و Flutter الأصلية على الرأس المحدد؛ النسخ الاصطناعي المشفر نجح ولا يحقق بوابة UAT.

**UAT:** لم ينشر أو يفعل هذا الفرع على UAT؛ الجدول غائب والأعلام مغلقة. أدلة بروتوكول التخزين التاريخية لا تحل محل البوابات.

**Android:** الاختبارات والبناء الآلي ناجحان للفرع؛ الميزة OFF فيحزمة 1359 الموحدة؛ لا اختبار هاتف لهذه الميزة.

**دليل القرار:** PR115:25success/0failure/1fallbackskip؛ اختبارات تذاكر/TUS/PG و Flutter الأصلية على الرأس المحدد؛ النسخ الاصطناعي المشفر نجح ولا يحقق بوابة UAT.؛ docs/IMAGE_TUS_UAT_BACKUP_RESTORE_AND_CANARY_GATE_AR.md؛ docs/AQER_BACKUP_RESTORE_ACTIVATION_2026-10-27_AR.md

**المانع النهائي:** اعتماد اتصال ووجهة حفظ آمنة واتساق DB/Storage، ونسخة كاملة مشفرة واستعادة مستقلة وفحص صلاحيات وخطة rollback وموافقة الهجرة.

**المورد والتكلفة/التفعيل:** يمكن dump و age واستعادة محلية مجانية دون Pro إذا توفرت الصلاحية والسعة؛ ضبط admission للـbucket المشترك وفق حد10MiB المقترح لحفظ وثائق KYC وإثبات الدفع، مع بقاء الإعلان8MiB والتحقق الخادمي؛ راجع بوابة Storage المصححة.

**اختبار ما بعد توفيره:** بعد البوابة فقط: الهجرة المحددة؛ RLS/GRANT/FK؛ canary6MiB ثم انقطاع/HEAD/PATCH وتجديد و offset و finalize ملتبس وتبديل حساب و cleanup و Android بعد قتل التطبيق.

**اختبار المالك — الدور:** الوسيط صاحب المسودة

**الخطوات:** تؤجل الرحلة حتى اجتياز البوابة، ثم اتبع خطة الاختبار بعد توفير المورد أعلاه. لا تفعّل علمًا لتجاوز هذه الخطوة.

**المتوقع:** نقل/عرض/تعافٍ آمن مع ثبات الملكية والمراجعة والتطهير وإيصال فشل حقيقي، دون تسريب أو نجاح وهمي.

**السلبي:** حساب آخر، ملف تالف/كبير، انقطاع، إعادةتسليم/ضغطمتكرر، قتل العملية، فشل التخزين والتنظيف، وتغير الحالة أثناء التنفيذ.

<a id="item-12"></a>

## 12 — الصور المتكيفة

**المتطلبات:** اختيار مشتق وفق مساحة العرض و DPR و metered/Data Saver، وتكبير صريح دون تحميل أصل حساس.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/network/adaptive_image_policy.dart`
- `mobile_app/lib/features/properties/presentation/adaptive_property_photo.dart`
- `backend-api-runtime/app/Services/ListingImageService.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#119](https://github.com/JJalal1/real-estate-uat-backend/pull/119) [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/adaptive_image_quality_test.dart", "mobile_app/test/adaptive_image_uat_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/AdaptiveImageQualityTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "اختيار النسخة بالشاشة/DPR وتوفير البيانات، بروتوكول صور HTTP و 304 و EXIF؛ تفاصيل العينة 765344→194483B وبطاقة 194483→39743B في القياس السابق المرتبط بالشفرة القائمة.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "Flutter/Laravel/Storage وقياس 304/بايتات؛ لا يساوي slow reader شبكة هاتف حقيقية.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** اختيار النسخة بالشاشة/DPR وتوفير البيانات، بروتوكول صور HTTP و 304 و EXIF؛ تفاصيل العينة 765344→194483B وبطاقة 194483→39743B في القياس السابق المرتبط بالشفرة القائمة.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** افتح قائمة ثم تفاصيل وصورة مكبرة على اتصال جيد وضعيف، مع Data Saver وتشغيل توفير البيانات.

**المتوقع:** البطاقة تستخدم صورة مناسبة لحجمها؛ التحميل الأعلى جودة عند الحاجة/الطلب، وتظل الملامح واضحة.

**السلبي:** انتقل سريعًا قبل انتهاء الصور؛ لا تظهر صورة عقار سابق أو يحمل حجمًا كاملًا بلا حاجة.

<a id="item-13"></a>

## 13 — التحميل الكسول

**المتطلبات:** طلب وسائط العناصر المرئية فقط وإيقاف الطلبات عند المغادرة/التمرير السريع.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/widgets/viewport_media.dart`
- `mobile_app/lib/features/properties/presentation/adaptive_property_photo.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/viewport_media_test.dart", "mobile_app/test/viewport_network_measurement_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "بوابة viewport ومسار/تبويب، إلغاء وقوائم تدريجية؛ عينة 21→2 طلب عند الفتح وعودة 0 تنزيل إضافي. ليس قياس scroll FPS على مودم Android.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "قياس الفتح 21→2 طلب سابق مثبت وإعادة فحوص HTTP الحالية؛ العودة دون طلبات إضافية في السيناريو المقاس.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** بوابة viewport ومسار/تبويب، إلغاء وقوائم تدريجية؛ عينة 21→2 طلب عند الفتح وعودة 0 تنزيل إضافي. ليس قياس scroll FPS على مودم Android.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** افتح قائمة طويلة ومرر ببطء ثم بسرعة وارجع للأعلى.

**المتوقع:** صور ما يظهر تُحمّل تدريجيًا؛ الرجوع يستفيد من الكاش.

**السلبي:** انقطاع وسط التمرير ثم عودة الشبكة وإعادة المحاولة دون بطاقات مكسورة دائمة.

<a id="item-14"></a>

## 14 — التخزين المؤقت

**المتطلبات:** TTL ومفاتيح فلاتر وحدود حجم وإبطال صحيح، وعزل حساب ومنع تخزين رد ملغى/سابق للطفرة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. حماية بدءالخروج و epoch الحالية تمنع بقاء ردود حساب قديم؛ مسار TUS الجديد محفوظ في PR115 فقط.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/network/api_client.dart`
- `mobile_app/lib/features/properties/data/property_repository.dart`
- `mobile_app/lib/features/account/presentation/actor_scoped_page.dart`

**الملفات التي تغيرت الآن:**

- `mobile_app/lib/features/account/data/auth_controller.dart`

**PRs:** [#128](https://github.com/JJalal1/real-estate-uat-backend/pull/128) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/public_discovery_cancellation_test.dart", "mobile_app/test/recent_properties_privacy_test.dart", "mobile_app/test/secondary_admin_recovery_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "اختبارات الرد المتأخر والطلبات الملغاة وإبطال الكاش بعد التعديل؛ فصل الهوية في مخازن خاصة وردود HTTP حقيقية؛ إصلاح متانة عزل صفحة التحقيق ضمن PR158.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "اختبارات Dio/HTTP/ملفات محلية فعلية وعزل الحساب؛ كاش الوسائط لا يوسع صلاحيات الخادم.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** اختبارات الرد المتأخر والطلبات الملغاة وإبطال الكاش بعد التعديل؛ فصل الهوية في مخازن خاصة وردود HTTP حقيقية؛ إصلاح متانة عزل صفحة التحقيق ضمن PR158.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم ثم الوسيط

**الخطوات:** افتح بيانات عقار ثم حدّثها من حساب الوسيط وعد إلى القائمة والتفاصيل؛ بدّل الحساب.

**المتوقع:** البيانات المتجددة لا يستبدلها رد قديم؛ لا تبقى بيانات خاصة بالحساب السابق.

**السلبي:** ابدأ طلبًا بطيئًا، غيّر الفلتر أو سجل الخروج قبل انتهائه؛ النتائج القديمة لا تعود.

<a id="item-15"></a>

## 15 — التعافي من أخطاء الشبكة

**المتطلبات:** حفظ العمل المؤكد والمدخلات عند timeout/503/429، retry الصحيح، ورفض النتائج القديمة ومسح البيانات عند فقد الصلاحية.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/properties/data/property_repository.dart`
- `mobile_app/lib/features/discovery/data/smart_search_session.dart`
- `backend-api-runtime/app/Http/Middleware/AuthenticateApiToken.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#129](https://github.com/JJalal1/real-estate-uat-backend/pull/129) [#134](https://github.com/JJalal1/real-estate-uat-backend/pull/134) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/listing_viewer_key_io_test.dart", "mobile_app/test/loading_recovery_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/AuthenticatedThrottleIsolationTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "503/timeout/429 في الاختبارات و HTTP، إبقاء النص والصفوف عند الفشل العابر، ورفض نجاح كتابة وهمي؛ لا يفعّل استئناف البايتات 11.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP 401/403/404/409/422/429 و 503/timeout محاكاة حقيقية/مضبوطة؛ quota لكل حساب مع إبقاء حد login العام.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** 503/timeout/429 في الاختبارات و HTTP، إبقاء النص والصفوف عند الفشل العابر، ورفض نجاح كتابة وهمي؛ لا يفعّل استئناف البايتات 11.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم والوسيط

**الخطوات:** افتح شاشة ثم افصل الاتصال، أعد المحاولة، وأعد الشبكة. جرّب حفظ مسودة عند انقطاع الاتصال.

**المتوقع:** رسالة واضحة وفعل إعادة محاولة يعمل؛ الحفظ الفاشل لا يعرض نجاحًا كاذبًا.

**السلبي:** 503 و 429 والمهلة آليًا؛ على الهاتف جرّب وضع الطيران ثم الرجوع دون فقد النص.

<a id="item-16"></a>

## 16 — حالات التحميل والفراغ والخطأ وإعادة المحاولة

**المتطلبات:** حالات واضحة ومتناسقة عبر الرحلات الأساسية والشاشات المرتبطة، وفصل الصفر عن الخطأ وعدم ظهور بيانات حساب سابق.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/widgets/app_components.dart`
- `mobile_app/lib/features/admin/presentation/platform_settings_screen.dart`
- `mobile_app/lib/features/developments/presentation/development_admin_screen.dart`
- `mobile_app/test/owner_active_screen_states_test.dart`
- `mobile_app/test/owner_secondary_privacy_layout_test.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#121](https://github.com/JJalal1/real-estate-uat-backend/pull/121) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#152](https://github.com/JJalal1/real-estate-uat-backend/pull/152) [#157](https://github.com/JJalal1/real-estate-uat-backend/pull/157) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/loading_recovery_test.dart", "mobile_app/test/buyer_loading_recovery_test.dart", "mobile_app/test/secondary_admin_recovery_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "35 شاشة بيانات×وضعين=70 حالة، مع حالات إضافية للنماذج والصفحات الخاصة والبوابات؛ إجمالي 156 حالة مركزة بعد PR158. inventory82 تعريف شاشة، لا نسبة تغطية 82/82.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "الرحلات الأساسية CI/HTTP خضراء؛ إصلاح شاشتين لا يثبت تلقائيًا كل واجهة ثانوية.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** 35 شاشة بيانات×وضعين=70 حالة، مع حالات إضافية للنماذج والصفحات الخاصة والبوابات؛ إجمالي 156 حالة مركزة بعد PR158. inventory82 تعريف شاشة، لا نسبة تغطية 82/82.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** كل الأدوار

**الخطوات:** اتبع سجل الشاشات المرفق: صفحة بيانات، حالة فارغة، انقطاع، إعادة المحاولة، ثم الخروج وتبديل الحساب.

**المتوقع:** لا شاشة تحميل دائمة أو نص استثناء تقني أو زر معطل بلا تفسير؛ أخطاء الشبكة قابلة للتعافي.

**السلبي:** شاشات التفاصيل والنماذج ومناطق الإدارة والنوافذ؛ الصلاحية المرفوضة لا تعرض بيانات قديمة. الخريطة الأصلية تحتاج القبول المباشر.

<a id="item-17"></a>

## 17 — تجميع علامات الخريطة

**المتطلبات:** تجميع ثابت دون فقد/تكرار علامة، واحترام التكبير والعلامة المحددة والحدود.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** تجميع قراءات overdue لملاك الصفحة مع حفظ السياسة والمبالغ والإشعار؛ قياس 20 مالكًا=9 استعلامات و 5 قراءات مستحقات عند 1 وعند 20، دون نمو N+1.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/map/domain/property_marker_cluster.dart`
- `mobile_app/lib/features/map/presentation/map_screen.dart`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Http/Controllers/Api/FinancialPropertyController.php`
- `backend-api-runtime/app/Services/PropertyFinancialService.php`
- `backend-api-runtime/app/Services/CompletePropertyFinancialService.php`

**PRs:** [#126](https://github.com/JJalal1/real-estate-uat-backend/pull/126) [#137](https://github.com/JJalal1/real-estate-uat-backend/pull/137) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/property_marker_cluster_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Postgres/PropertyMarketContextPostgresTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "اختبار مستويات zoom8..19 وعدم فقد أو تكرار العلامات والعزل والفراغ؛ Native gestures والإطارات والضغط تحتاج هاتف المالك.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "سلامة Dart و EXPLAIN لفهرس location؛ rendering/gestures Native ليست نتيجة SQL.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** اختبار مستويات zoom8..19 وعدم فقد أو تكرار العلامات والعزل والفراغ؛ Native gestures والإطارات والضغط تحتاج هاتف المالك.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** افتح الخريطة، كبّر وصغّر واضغط تجمعًا ثم علامة منفردة؛ ارجع للقائمة.

**المتوقع:** التجمعات تتغير مع مستوى التكبير وتفتح العقار الصحيح دون تجمد ملحوظ.

**السلبي:** كرر على هاتف محدود الذاكرة واتصال ضعيف؛ قياس سلاسة Native لم يُستبدل باختبار Widget.

<a id="item-18"></a>

## 18 — الصفحات والتحميل التدريجي

**المتطلبات:** صفحات مستقرة بلا تداخل، retry الصفحة الفاشلة، dedup وتوقف عند نهاية النتائج.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** تجميع قراءات overdue لملاك الصفحة مع حفظ السياسة والمبالغ والإشعار؛ قياس 20 مالكًا=9 استعلامات و 5 قراءات مستحقات عند 1 وعند 20، دون نمو N+1.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/discovery/data/smart_search_session.dart`
- `mobile_app/lib/features/properties/data/property_repository.dart`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Http/Controllers/Api/FinancialPropertyController.php`
- `backend-api-runtime/app/Services/PropertyFinancialService.php`
- `backend-api-runtime/app/Services/CompletePropertyFinancialService.php`

**PRs:** [#129](https://github.com/JJalal1/real-estate-uat-backend/pull/129) [#137](https://github.com/JJalal1/real-estate-uat-backend/pull/137) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/smart_search_pagination_recovery_test.dart", "mobile_app/test/discovery_http_acceptance_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "HTTP صفحات وتراجع الصفحة الفاشلة وعدم التداخل؛ اختبارات البحث والدعم والرسائل؛ بقاء الصفحة الأولى وإعادة المحاولة المباشرة. الهاتف باقٍ.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP حقيقي و PG؛ العينة العامة لا تثبت كل قائمة خاصة على هاتف.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** HTTP صفحات وتراجع الصفحة الفاشلة وعدم التداخل؛ اختبارات البحث والدعم والرسائل؛ بقاء الصفحة الأولى وإعادة المحاولة المباشرة. الهاتف باقٍ.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم والوسيط والدعم

**الخطوات:** مرر نتائج البحث والإعلانات والوارد حتى الصفحة التالية؛ افصل الشبكة عند تحميل صفحة لاحقة ثم أعدها واضغط إعادة المحاولة.

**المتوقع:** الصفحة الأولى تبقى؛ تعاد الصفحة الفاشلة ويكمل التصفح دون تكرار أو فقد الصفوف.

**السلبي:** غير الفلتر أثناء تحميل صفحة لاحقة؛ لا تختلط صفحات البحثين.

<a id="item-19"></a>

## 19 — Debounce وإلغاء الطلبات

**المتطلبات:** تأخير الطلب المناسب وإلغاء النقل ورفض الردود المعكوسة وعدم إعادة ملء الكاش بنتيجة ملغاة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. حماية بدءالخروج و epoch الحالية تمنع بقاء ردود حساب قديم؛ مسار TUS الجديد محفوظ في PR115 فقط.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/network/api_client.dart`
- `mobile_app/lib/features/discovery/data/smart_search_session.dart`
- `mobile_app/lib/features/developments/presentation/development_admin_screen.dart`

**الملفات التي تغيرت الآن:**

- `mobile_app/lib/features/account/data/auth_controller.dart`

**PRs:** [#128](https://github.com/JJalal1/real-estate-uat-backend/pull/128) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/public_discovery_cancellation_test.dart", "mobile_app/test/secondary_admin_recovery_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "Debounce وإلغاء/generation وردود معكوسة وتغيير فلتر/dispose؛ اختبارات منع استجابة بحث قديم وإبطال أدلة خاصة قديمة ضمن PR158.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "اختبارات تأخير/ردود معكوسة وإلغاء عبر Dio/HTTP؛ لا نتيجة قديمة تحل محل الجديدة.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** Debounce وإلغاء/generation وردود معكوسة وتغيير فلتر/dispose؛ اختبارات منع استجابة بحث قديم وإبطال أدلة خاصة قديمة ضمن PR158.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** اكتب البحث بسرعة، وغيّر النوع والمحافظة عدة مرات مع اتصال بطيء.

**المتوقع:** النتيجة النهائية تطابق آخر طلب فقط؛ لا تومض نتائج طلب ملغى.

**السلبي:** ارجع قبل انتهاء الطلب وأعد فتح البحث؛ لا استثناء بعد إغلاق الشاشة.

<a id="item-20"></a>

## 20 — Prefetch المشروط

**المتطلبات:** يبقى OFF ما لم يثبت قياس فائدة صافية مع تكلفة بيانات وإشارة metered موثوقة.

**السابق:** OFF معتمد مشروط

**المنجز الآن:** اعتماد قرار OFF وفق توجيه المالك الحالي؛ لا تفعيل ولا حاجة لاختراع تجربة تشغيل ناجحة.

**القرار:** مكتمل ومعتمد. اجتاز شروط الاعتماد ضمن النطاق.

**الملفات المراجعة:**

- `mobile_app/lib/core/widgets/viewport_media.dart`
- `mobile_app/lib/core/network/api_client.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/viewport_network_measurement_test.dart", "mobile_app/test/adaptive_image_quality_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "محفوظ OFF وفق قرار المالك. لم نجمع تجربة مقارنة تشغيل جديدة تكفي لإثبات صافي فائدة الوقت/البايتات/الذاكرة؛ لا تفعيل تلقائي.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "القياسات الحالية تثبت viewport/cache وإعادة استخدام البايتات، ولا تثبت فائدة ON.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** محفوظ OFF وفق قرار المالك. لم نجمع تجربة مقارنة تشغيل جديدة تكفي لإثبات صافي فائدة الوقت/البايتات/الذاكرة؛ لا تفعيل تلقائي.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** لا مانع خاص بالبند ضمن نطاقه المعتمد.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** قرار التشغيل

**الخطوات:** لا تفعّل Prefetch في هذه الجولة. راقب سلوك التصفح العادي فقط.

**المتوقع:** يبقى OFF بالقرار المعتمد حتى تجربة تُثبت صافي فائدة الوقت مقابل البايتات والذاكرة.

**السلبي:** لا نختبر تفعيله على اتصال المالك المدفوع لمجرد إغلاق بند.

<a id="item-21"></a>

## 21 — تشغيل الفيديو على Android

**المتطلبات:** تشغيل مشتق آمن عند الطلب و Range/seek وأذونات وتعافٍ و lifecycle، مع رفض محتوى غير مراجع أو غير مصرح به.

**السابق:** مؤجل وموقوف بقرار البوابة؛ PR111 Draft غير مدموج.

**المنجز الآن:** مقارنة الفرع القديم مع UAT الحالي وحل التعارضات مع حفظ حمايات الصور والجلسات؛ attempt fencing ومفاتيح مشتقات مستقلة و tombstones وحذف آمن مع كاتب نشط وفشل مزود، bucket فيديو مستقل لا يوسع TUS، metadata من الناتج، وقف playback بالخلفية، Docker و FFmpeg و kill137 ثم تعافٍ.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. بعد التشغيل الحقيقي المقاس يصبح 2؛ بعد قبول مشاهدة المالك والأذونات والتعافي يصبح 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Jobs/ProcessListingVideo.php`
- `backend-api-runtime/app/Models/ListingVideo.php`
- `backend-api-runtime/app/Http/Controllers/Api/ListingVideoController.php`
- `backend-api-runtime/app/Http/Controllers/Api/PropertyController.php`
- `backend-api-runtime/app/Services/CloudAssetStorageService.php`
- `backend-api-runtime/app/Services/ListingVideoTranscoder.php`
- `backend-api-runtime/app/Services/AccountErasureService.php`
- `backend-api-runtime/database/migrations/2026_10_23_000100_create_listing_videos_table.php`
- `backend-api-runtime/Dockerfile.video-worker`
- `mobile_app/lib/features/properties/presentation/property_video_section.dart`
- `scripts/probe_video_worker_container.py`

**الملفات التي تغيرت الآن:**

- `backend-api-runtime/app/Jobs/ProcessListingVideo.php`
- `backend-api-runtime/app/Models/ListingVideo.php`
- `backend-api-runtime/app/Http/Controllers/Api/ListingVideoController.php`
- `backend-api-runtime/app/Http/Controllers/Api/PropertyController.php`
- `backend-api-runtime/app/Services/CloudAssetStorageService.php`
- `backend-api-runtime/app/Services/ListingVideoTranscoder.php`
- `backend-api-runtime/app/Services/AccountErasureService.php`
- `backend-api-runtime/database/migrations/2026_10_23_000100_create_listing_videos_table.php`
- `backend-api-runtime/Dockerfile.video-worker`
- `mobile_app/lib/features/properties/presentation/property_video_section.dart`
- `scripts/probe_video_worker_container.py`

**PRs:** [#111](https://github.com/JJalal1/real-estate-uat-backend/pull/111)

**SHAs:** tested_feature_head=`d29d4c09e8a4e5efc18f3facdd6ce9397b3cd32e`؛ current_integrated_engineering_base=`ca3ced8f60eed067ce1406b6661bcc583274199f`

**Flutter:** {"result": "PASS on feature head; Android handset not tested", "files": ["mobile_app/test/property_video_section_test.dart", "mobile_app/test/stage9_review_models_test.dart"]}

**Laravel:** {"result": "PASS on feature head", "files": ["backend-api-runtime/tests/Feature/ListingVideoApiTest.php", "backend-api-runtime/tests/Feature/ListingVideoFullCycleTest.php", "backend-api-runtime/tests/Feature/ListingVideoTranscoderTest.php", "backend-api-runtime/tests/Feature/ListingVideoStreamTest.php", "backend-api-runtime/tests/Feature/VideoCloudStorageProtocolTest.php"]}

**PostgreSQL و Storage:** {"result": "Disposable PostgreSQL PASS; source/permission/storage protocol regressions PASS; no live DDL or feature activation", "files": ["backend-api-runtime/tests/Postgres/ListingVideoPostgresTest.php"]}

**CI:** PR111:26success/0failure/1fallbackskip؛ 50 اختبار قبول/Storage و 299assertions، 7Flutter موجهة وبناء Android، تحويل 2s→720p≈702–707ms و RSSchild≈181MiB، و SIGKILL137 لحاوية FFmpeg ثمتحويلناجح؛ ليس قتل queuelease حقيقيًا.

**UAT:** لم ينشر أو يفعل هذا الفرع على UAT؛ الجدول غائب والأعلام مغلقة. أدلة بروتوكول التخزين التاريخية لا تحل محل البوابات.

**Android:** الاختبارات والبناء الآلي ناجحان للفرع؛ الميزة OFF فيحزمة 1359 الموحدة؛ لا اختبار هاتف لهذه الميزة.

**دليل القرار:** PR111:26success/0failure/1fallbackskip؛ 50 اختبار قبول/Storage و 299assertions، 7Flutter موجهة وبناء Android، تحويل 2s→720p≈702–707ms و RSSchild≈181MiB، و SIGKILL137 لحاوية FFmpeg ثمتحويلناجح؛ ليس قتل queuelease حقيقيًا.؛ docs/VIDEO_CURRENT_BASE_REVIEW_2026-10-26_AR.md؛ docs/AQER_BACKUP_RESTORE_ACTIVATION_2026-10-27_AR.md

**المانع النهائي:** تفعيل 3 الآمن وعامل و Storage ومراجعة بشرية، ثم تشغيل Android فعلي و Range على المورد المعتمد.

**المورد والتكلفة/التفعيل:** العامل نفسه المطلوب للبند 3؛ لا مورد معالجة إضافي تلقائيًا. رسوم الفيديو تأتي من worker/storage/egress.

**اختبار ما بعد توفيره:** جاهزية مشتق H264/AAC و poster، 206/416 و seek و play/pause/lifecycle/rotation/انقطاع، حساب آخر ورفض غير مراجع، ومراقبة bytes/RSS.

**اختبار المالك — الدور:** مالك مسودة ثم مراجع ثم باحث

**الخطوات:** تؤجل الرحلة حتى اجتياز البوابة، ثم اتبع خطة الاختبار بعد توفير المورد أعلاه. لا تفعّل علمًا لتجاوز هذه الخطوة.

**المتوقع:** نقل/عرض/تعافٍ آمن مع ثبات الملكية والمراجعة والتطهير وإيصال فشل حقيقي، دون تسريب أو نجاح وهمي.

**السلبي:** حساب آخر، ملف تالف/كبير، انقطاع، إعادةتسليم/ضغطمتكرر، قتل العملية، فشل التخزين والتنظيف، وتغير الحالة أثناء التنفيذ.

<a id="item-22"></a>

## 22 — Deep Links و App Links

**المتطلبات:** قبول المسارات والأصول المسموح بها فقط، و HTTPS موثق بدومين وتوقيع رسميين وفتح Native صحيح.

**السابق:** مانع خارجي محدد — غير جاهز للاعتماد النهائي

**المنجز الآن:** تثبيت flavor وهوية UAT الجديدة وحماية Production؛ زوج 1358/1359 بنفس الشهادة، ومحاكي API36 وحفظ ملفي fixture؛ مراجعة الروابط/الأذونات والتحديث دون ادعاء Play أو هاتف.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. عند إثبات التحقق الرسمي يصبح 2؛ قبول المالك علىنسخة موقعة معتمدة يجعله 1.

**الملفات المراجعة:**

- `mobile_app/lib/router/app_deep_links.dart`
- `mobile_app/android/app/src/main/AndroidManifest.xml`
- `backend-api-runtime/app/Services/AndroidAppLinkAssociation.php`

**الملفات التي تغيرت الآن:**

- `mobile_app/android/app/build.gradle`
- `mobile_app/android/app/src/main/AndroidManifest.xml`
- `scripts/verify_built_uat_apk.py`
- `scripts/probe_uat_android_upgrade.py`

**PRs:** [#123](https://github.com/JJalal1/real-estate-uat-backend/pull/123) [#133](https://github.com/JJalal1/real-estate-uat-backend/pull/133) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/deep_link_origin_guard_test.dart", "mobile_app/test/phase3_deep_links_test.dart", "mobile_app/test/phase4_deep_links_test.dart", "mobile_app/test/phase5_deep_links_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "مسارات allowlist ورفض URI مشوه ومضيف/منفذ/اعتماد غير مسموح؛ assetlinks يقبل بصمات 32-byte سليمة وحزمة reverse-DNS فقط. [] آمنة عند غياب الهوية الرسمية.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "عقود المسار والتحصين CI؛ ذلك لا يثبت ارتباط Android بالدومين.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** مسارات allowlist ورفض URI مشوه ومضيف/منفذ/اعتماد غير مسموح؛ assetlinks يقبل بصمات 32-byte سليمة وحزمة reverse-DNS فقط. [] آمنة عند غياب الهوية الرسمية.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** اسم HTTPS رسمي وهوية وتوقيع معتمدان، ونشر assetlinks والتحقق الحقيقي من Android.

**المورد والتكلفة/التفعيل:** قرار الدومين و DNS/TLS؛ السعر حسب الاسم/TLD والتجديد، لم يُحجز شيء. بصمة Play لا تُستبدل ببصمة UAT المؤقتة.

**اختبار ما بعد توفيره:** assetlinks صالح للمضيف/الحزمة/الشهادة؛ adb verify-app-links وفتح منخارج التطبيق مغلقًا/مفتوحًا، والعودة بعد login ورفض الروابط الخبيثة/المضيف/المنفذ.

**اختبار المالك — الدور:** زائر ومستخدم مسجل

**الخطوات:** جرّب realestate://app/properties/60 وروابط UAT من خارج التطبيق، في حال الإغلاق والفتح وتسجيل الدخول.

**المتوقع:** الرابط المسموح يفتح الوجهة الصحيحة؛ الروابط المزيفة أو المشوهة تُرفض.

**السلبي:** HTTPS App Links التلقائية تنتظر دومين وشهادة Play حقيقيين؛ لا يُعلن اعتمادها بمجرد custom scheme.

<a id="item-23"></a>

## 23 — العقارات المشاهدة مؤخرًا

**المتطلبات:** سجل محدود مرتب بلا تكرار ومعزول لكل حساب/زائر، مع كتابة ذرية وتعافي فشل الملفات.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/properties/data/recent_properties_store.dart`
- `mobile_app/lib/features/properties/presentation/recent_properties_screen.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/recent_properties_privacy_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "ملف منفصل لكل حساب/زائر، IO متسلسل وكتابة ذرية وحد 30 ومنع التكرار ومحو؛ اختبارات فشل التخزين وإعادة المحاولة وعزل الحساب.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "تخزين محلي فقط؛ لا DB أو migration مطلوب؛ الملفات والردود المتأخرة واختبارات العزل مثبتة.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** ملف منفصل لكل حساب/زائر، IO متسلسل وكتابة ذرية وحد 30 ومنع التكرار ومحو؛ اختبارات فشل التخزين وإعادة المحاولة وعزل الحساب.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم ثم حساب آخر

**الخطوات:** افتح عدة عقارات؛ افتح «شوهد مؤخرًا» وأغلق التطبيق وافتحه، ثم بدّل الحساب وامسح السجل.

**المتوقع:** ترتيب وحد 30 دون تكرار، محفوظ على الجهاز ومعزول حسب الحساب/الزائر.

**السلبي:** لا يظهر سجل الحساب الأول للثاني، وفشل التخزين لا يوقف فتح العقار.

<a id="item-24"></a>

## 24 — حفظ حالة الاستكشاف والعودة إليها

**المتطلبات:** الحفاظ على الفلاتر والخريطة والقائمة وسجل البحث بصورة ذرية مع عودة متسقة وعدم سباق كتابة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/map/data/property_discovery_history_store.dart`
- `mobile_app/lib/features/map/presentation/map_screen.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#127](https://github.com/JJalal1/real-estate-uat-backend/pull/127) [#128](https://github.com/JJalal1/real-estate-uat-backend/pull/128)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/property_discovery_history_atomic_test.dart", "mobile_app/test/viewport_network_measurement_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "حفظ فلاتر/خريطة/سجل البحث متسلسل وذري، PageStorage وكاش؛ اختبارات حفظ متزامن و IO retry وعودة بلا تنزيل مكرر في العينة.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "filesystem حقيقي و HTTP عودة دون نقل إضافي في السيناريو المثبت.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** حفظ فلاتر/خريطة/سجل البحث متسلسل وذري، PageStorage وكاش؛ اختبارات حفظ متزامن و IO retry وعودة بلا تنزيل مكرر في العينة.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** حدد فلاتر وموضع خريطة وابحث؛ افتح عقارًا ثم ارجع؛ أغلق التطبيق وافتحه.

**المتوقع:** تعود حالة الاستكشاف والفلاتر المتوقعة دون إعادة ضبط أو تنزيل زائد غير مبرر.

**السلبي:** عد أثناء طلب متأخر وكرر الحفظ السريع؛ الحالة الأحدث تبقى.

<a id="item-25"></a>

## 25 — تجربة عدم وجود نتائج

**المتطلبات:** عرض الصفر كحالة صحيحة مع تعديل معايير واضح، وتمييزه عن HTTP فاشل أو قائمة قديمة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/features/discovery/presentation/smart_search_assistant.dart`
- `mobile_app/lib/features/discovery/data/smart_search_session.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/buyer_loading_recovery_test.dart", "mobile_app/test/discovery_http_acceptance_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "حالات no-results منفصلة عن خطأ الشبكة، تعديل/مسح الفلاتر؛ اختبارات Empty→503→Retry و UAT بعبارة اصطناعية لا تطابق شيئًا.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP 200 مع data=[] و meta.total=0، و Flutter يفرق بينها وبين 503.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** حالات no-results منفصلة عن خطأ الشبكة، تعديل/مسح الفلاتر؛ اختبارات Empty→503→Retry و UAT بعبارة اصطناعية لا تطابق شيئًا.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** زائر

**الخطوات:** ابحث بعبارة «zzzz-owner-no-match-20261026»، ثم عدّل المعايير أو امسحها.

**المتوقع:** رسالة عدم وجود نتائج مع طريق واضح لتعديل البحث، وليست رسالة عطل.

**السلبي:** افصل الإنترنت: يظهر خطأ وإعادة محاولة بدل الادعاء أن النتائج صفر.

<a id="item-26"></a>

## 26 — التحقق من تحديث التطبيق

**المتطلبات:** قرار إجباري/اختياري صحيح حسب رقم البناء الفعلي، وفتح متجر مسموح وآمن وإتاحة تحديث رسمي متوافق.

**السابق:** مانع خارجي محدد — غير جاهز للاعتماد النهائي

**المنجز الآن:** تثبيت flavor وهوية UAT الجديدة وحماية Production؛ زوج 1358/1359 بنفس الشهادة، ومحاكي API36 وحفظ ملفي fixture؛ مراجعة الروابط/الأذونات والتحديث دون ادعاء Play أو هاتف.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. زوج 1358→1359 يثبت replacement محددًا فقط؛ بعد إعداد Play واختباره يصبح 2، وقبول المالك مع شروط الإصدار 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/release/release_gate.dart`
- `backend-api-runtime/app/Http/Controllers/Api/ReleaseController.php`
- `.github/workflows/broker-experience-ci.yml`
- `scripts/probe_uat_android_upgrade.py`

**الملفات التي تغيرت الآن:**

- `mobile_app/android/app/build.gradle`
- `mobile_app/android/app/src/main/AndroidManifest.xml`
- `scripts/verify_built_uat_apk.py`
- `scripts/probe_uat_android_upgrade.py`

**PRs:** [#131](https://github.com/JJalal1/real-estate-uat-backend/pull/131) [#139](https://github.com/JJalal1/real-estate-uat-backend/pull/139) [#141](https://github.com/JJalal1/real-estate-uat-backend/pull/141) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) [#156](https://github.com/JJalal1/real-estate-uat-backend/pull/156) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/release_gate_store_uri_test.dart", "mobile_app/test/uat_compiled_environment_test.dart", "mobile_app/test/push_registration_guard_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "اختبارات optional/mandatory وإلزام رابط المتجر بمعرف الحزمة ورفض URI ضار؛ API36 A→B بنفس الشهادة مع مقارنة بصمات ملفَي مظهر واستعادة قبل/بعد الإطلاق دون شبكة.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "API/Flutter وبناء فعلي؛ API36 و ELF/ZIP لا يغنيان عن اختبار upgrade موقع.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** اختبارات optional/mandatory وإلزام رابط المتجر بمعرف الحزمة ورفض URI ضار؛ API36 A→B بنفس الشهادة مع مقارنة بصمات ملفَي مظهر واستعادة قبل/بعد الإطلاق دون شبكة.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** مفتاح UAT ثابت لسلاسل البناء المستقبلية، و Production package و PlayAppSigning ورابط المتجر الرسمي واختبار تحديث Play.

**المورد والتكلفة/التفعيل:** إنشاء/حفظ مفتاح Android لايتطلب اشتراكشهادة؛ PlayConsole25 دولارًا مرةواحدة، ولا تسجيل/نشر الآن.

**اختبار ما بعد توفيره:** تحقق build/version وعدم downgrade ومساري optional/mandatory وروابط allowlist؛ ثم A→B عبر PlayInternal مع حفظ الجلسة/البيانات والهجرات المطلوبة.

**اختبار المالك — الدور:** المالك — زوج UAT

**الخطوات:** ثبّت النسخة A ثم احفظ مسودة ومظهرًا؛ حدّث إلى B المتوافقة في الشهادة دون إزالة A؛ تحقق من البيانات. بوابتا الاختياري والإجباري لهما اختبارات آلية مستقلة.

**المتوقع:** زيادة رقم البناء وبقاء الملفات الخاصة؛ الاختياري يمكن تأجيله، والإجباري يمنع الاستمرار عندما يكون هناك رابط متجر صحيح.

**السلبي:** الزوج من المصدر نفسه دليل ميكانيكية تحديث UAT؛ تحديث Play وقبول السياسة النهائية يحتاجان هوية المتجر والتوقيع الرسميين.

<a id="item-27"></a>

## 27 — الصلاحيات عند الحاجة

**المتطلبات:** طلب الموقع/الكاميرا/الميكروفون عند الاستخدام، مع رفض ودائم وخدمة متوقفة وعودة من الإعدادات دون إجبار.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** تثبيت flavor وهوية UAT الجديدة وحماية Production؛ زوج 1358/1359 بنفس الشهادة، ومحاكي API36 وحفظ ملفي fixture؛ مراجعة الروابط/الأذونات والتحديث دون ادعاء Play أو هاتف.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/platform/app_permission_settings.dart`
- `mobile_app/lib/core/platform/stage5_media_picker.dart`
- `mobile_app/lib/core/platform/voice_capture_controller.dart`

**الملفات التي تغيرت الآن:**

- `mobile_app/android/app/build.gradle`
- `mobile_app/android/app/src/main/AndroidManifest.xml`
- `scripts/verify_built_uat_apk.py`
- `scripts/probe_uat_android_upgrade.py`

**PRs:** [#125](https://github.com/JJalal1/real-estate-uat-backend/pull/125) [#141](https://github.com/JJalal1/real-estate-uat-backend/pull/141) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/uat_map_location_picker_test.dart", "mobile_app/test/user_work_media_test.dart", "mobile_app/test/live_dictation_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "طلبات الأذونات عند الفعل ومسارات الرفض/الإعدادات؛ Manifest/built APK مستهدف 36/min23. سلوك منتقي الصور والموقع ورفض الإذن في النظام يحتاج الهاتف.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "واجهات bridge ومواقف الرفض مختبرة بصورة آلية؛ نظام الإذن Native يحتاج جهازًا.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** طلبات الأذونات عند الفعل ومسارات الرفض/الإعدادات؛ Manifest/built APK مستهدف 36/min23. سلوك منتقي الصور والموقع ورفض الإذن في النظام يحتاج الهاتف.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** المستخدم

**الخطوات:** اضغط «موقعي» أو إضافة صورة حين تحتاجها فقط؛ ارفض الإذن، ثم ارفض دائمًا وعد من إعدادات النظام.

**المتوقع:** لا أذونات مفاجئة عند البداية؛ رفض مفهوم وخيار إعدادات اختياري؛ تعمل المحاولة بعد منح الإذن.

**السلبي:** اختبر تعطيل خدمة الموقع و Android13+ للإشعارات عند تفعيل FCM لاحقًا.

<a id="item-28"></a>

## 28 — خصوصية EXIF

**المتطلبات:** لا تُعرض metadata الكاميرا/GPS الحساسة؛ أصل خاص، ترميز عرض نظيف واتجاه صحيح وعدم إتاحة variant=original.

**السابق:** مكتمل ومعتمد

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** مكتمل ومعتمد. اجتاز شروط الاعتماد ضمن النطاق.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/ListingImageService.php`
- `backend-api-runtime/app/Services/ProfessionalPhotoService.php`
- `backend-api-runtime/app/Services/CloudAssetStorageService.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": [], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/ProfessionalPhotoPrivacyTest.php", "backend-api-runtime/tests/Feature/AdaptiveImageQualityTest.php", "backend-api-runtime/app/Console/Commands/UatRoleJourneys.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "ترميز المشتقات يحذف EXIF/GPS ويتعامل مع الاتجاه؛ JPEGs حية ومقارنة EXIF ورفض الأصل والوصول غير المصرح. صور الاختبار لا تتضمن بيانات بشرية.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "صور JPEG اصطناعية بوسم EXIF/GPS، غياب الوسم من العرض واتجاه محفوظ، رفض original422 وملكية 404، bucket خاص.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** ترميز المشتقات يحذف EXIF/GPS ويتعامل مع الاتجاه؛ JPEGs حية ومقارنة EXIF ورفض الأصل والوصول غير المصرح. صور الاختبار لا تتضمن بيانات بشرية.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** لا مانع خاص بالبند ضمن نطاقه المعتمد.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** الوسيط

**الخطوات:** فحص تراجع اختياري: ارفع صورة EXIF اصطناعية ثم افتح مشتقات العرض العامة.

**المتوقع:** بيانات الكاميرا/GPS محذوفة من العرض؛ الاتجاه صحيح؛ موضع العقار يأتي من اختيار المستخدم.

**السلبي:** الأصل الخاص/إثبات الملكية غير عام؛ لا تستخدم صورة وثيقة بشرية للفحص.

<a id="item-29"></a>

## 29 — إدارة صور الإعلانات

**المتطلبات:** ترتيب/رئيسية/حذف/استبدال وإعادة رفع آمنة، مع حماية المراجع ودون ملفات يتيمة من المسار المختبر.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/ListingEditorDraftService.php`
- `backend-api-runtime/app/Services/ListingImageService.php`
- `mobile_app/lib/features/properties/presentation/listing_editor_screen.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#138](https://github.com/JJalal1/real-estate-uat-backend/pull/138) [#140](https://github.com/JJalal1/real-estate-uat-backend/pull/140) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/user_work_media_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/CloudDeleteLifecycleTest.php", "backend-api-runtime/tests/Feature/UserWorkMediaTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "ترتيب/رئيسية/استبدال/حذف وملكية المسودة ومراجعة البصمة؛ HTTP و Storage حقيقيان واختبارات مراجعة الصور؛ لا موافقة موروثة لصورة جديدة.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "Flutter contracts و HTTP/PG/Storage حقيقي وصفر مراجع/أصول fixture بعد التنظيف؛ لا حذف لصور غير مستخدمي الاختبار.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** ترتيب/رئيسية/استبدال/حذف وملكية المسودة ومراجعة البصمة؛ HTTP و Storage حقيقيان واختبارات مراجعة الصور؛ لا موافقة موروثة لصورة جديدة.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** الوسيط ثم المراجع

**الخطوات:** على الإعلان الاصطناعي غيّر ترتيب الصور والرئيسية، احذف واحدة واستبدل أخرى، ثم احفظ وأعد فتحه.

**المتوقع:** الترتيب والرئيسية محفوظان، والصورة المستبدلة تحتاج مراجعة جديدة.

**السلبي:** افصل الاتصال أثناء الحفظ، وأعد المحاولة، وافتح مسودة من الحساب الآخر للتأكد من الرفض.

<a id="item-30"></a>

## 30 — المسودات واستعادتها

**المتطلبات:** checkpoint/revision مستقر واستعادة دون تكرار، وحماية التأخير وتبديل الحساب وحفظ العمل عند الشبكة الضعيفة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة. حماية بدءالخروج و epoch الحالية تمنع بقاء ردود حساب قديم؛ مسار TUS الجديد محفوظ في PR115 فقط.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/ListingEditorDraftService.php`
- `mobile_app/lib/features/properties/data/listing_account_draft_repository.dart`
- `mobile_app/lib/features/properties/presentation/listing_editor_screen.dart`

**الملفات التي تغيرت الآن:**

- `mobile_app/lib/features/account/data/auth_controller.dart`

**PRs:** [#120](https://github.com/JJalal1/real-estate-uat-backend/pull/120) [#140](https://github.com/JJalal1/real-estate-uat-backend/pull/140) [#160](https://github.com/JJalal1/real-estate-uat-backend/pull/160)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/loading_recovery_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Postgres/ListingEditorDraftPostgresTest.php", "backend-api-runtime/tests/Feature/AccountErasureLaunchTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "محفوظات الجهاز وخادم المسودات و revision/checkpoint، استعادة بعد فشل التخزين ورفض مسودة حساب آخر؛ مسودة وصورة خاصة معدتان في preflight. ليس TUS11.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP/PG وملفات و revision، مع رفض قراءة حساب آخر وعدم تكرار ملف عند retry.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** محفوظات الجهاز وخادم المسودات و revision/checkpoint، استعادة بعد فشل التخزين ورفض مسودة حساب آخر؛ مسودة وصورة خاصة معدتان في preflight. ليس TUS11.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** الوسيط

**الخطوات:** افتح مسودة الاستعادة المعدّة؛ اكتب نصًا وأضف صورة؛ احفظ أو اترك استعادة الجهاز، أغلق التطبيق قسرًا ثم افتحه وأكمل.

**المتوقع:** النص والترتيب والصور المحفوظة تعود للحساب نفسه، وتظهر نتيجة الحفظ بوضوح.

**السلبي:** انقطاع الرفع/الخروج/نقر استعادة مرتين/تبديل الحساب؛ لا يفتح محرران ولا تضيع النسخة الأحدث. هذا ليس استئناف البايتات 11.

<a id="item-31"></a>

## 31 — حذف الحساب

**المتطلبات:** حذف هوية وتوكنات/عمل عابر وإثباتات خاصة وأرشفة الإعلان، مع الاحتفاظ المحدد بالسجلات القانونية ورفض حذف الموظف بلا نقل صلاحيات.

**السابق:** مانع خارجي محدد — غير جاهز للاعتماد النهائي

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز هندسيًا وموقوف انتظارًا لمورد أو اعتماد خارجي. اعتماد السياسة وتشغيل الويب/OTP والهوية يتيح 2؛ قبول الرحلة الفعلية 1. نجاح UAT لا يجيز حذف حساب بشري.

**الملفات المراجعة:**

- `backend-api-runtime/app/Services/AccountErasureService.php`
- `backend-api-runtime/app/Http/Middleware/AuthenticateApiToken.php`
- `mobile_app/lib/features/account/presentation/account_safety_screen.dart`
- `backend-api-runtime/tests/Feature/AccountErasureAuthRaceTest.php`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#122](https://github.com/JJalal1/real-estate-uat-backend/pull/122) [#140](https://github.com/JJalal1/real-estate-uat-backend/pull/140) [#153](https://github.com/JJalal1/real-estate-uat-backend/pull/153) [#155](https://github.com/JJalal1/real-estate-uat-backend/pull/155) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/launch_readiness_wave4_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": ["backend-api-runtime/tests/Feature/AccountErasureLaunchTest.php", "backend-api-runtime/tests/Feature/AuthenticatedThrottleIsolationTest.php"], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "AccountErasureLaunchTest: فشل Storage يرجع بيانات المعاملة ثم نجاح retry، إلغاء الجلسات وحفظ المرجع المشترك. AuthRaceTest:5 سباقات؛ اختبارات PostgreSQL؛ لا حذف حساب بشري.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "HTTP/DB/Storage حقيقي لحساب اصطناعي؛ 401 بعد الحذف، أصل المسودة والصورة المهنية غائبان، المحاضر والرسائل المشتركة محفوظة وفق القواعد.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** AccountErasureLaunchTest: فشل Storage يرجع بيانات المعاملة ثم نجاح retry، إلغاء الجلسات وحفظ المرجع المشترك. AuthRaceTest:5 سباقات؛ اختبارات PostgreSQL؛ لا حذف حساب بشري.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** اعتماد سياسة حذف/احتفاظ للبيانات والوسائط المؤرشفة وحقوق الوصول، ومزود OTP لليمن وصفحة حذف Production وقبول الهاتف.

**المورد والتكلفة/التفعيل:** قرار سياسة بلا مدة أو مسوغ قانوني مختلق؛ OTP حسب المزود والقناة. مرجع Twilio0.05 دولار/تحقق+القناة، ليس عرض اليمن.

**اختبار ما بعد توفيره:** expired/wrong/reusedOTP و throttle؛ جلسةقديمة؛ storagefailure/retry وسباقاتالحذف والمراجعالمشتركة؛ تدقيق البيان المنشور وصفحةالويب.

**اختبار المالك — الدور:** حساب الحذف الاصطناعي فقط

**الخطوات:** استعمل حساب الحذف المنفصل في كبسولة الوصول؛ أنشئ بيانات اصطناعية، افتح الحذف واقرأ الأثر، ثم أكّد العبارة؛ حاول استعمال الجلسة القديمة.

**المتوقع:** تمحى الهوية وتلغى الجلسات وتزال وثائق التحقق والمسودات غير المشتركة؛ تؤرشف الإعلانات وتُحفظ مراجعها والسجلات المشتركة وفق السياسة المطلوب اعتمادها. لا تعني العملية مسح كل ملف مرتبط بإعلان مؤرشف.

**السلبي:** فشل Storage/سباقات OTP مثبتة آليًا؛ سياسة الاحتفاظ ومزود OTP وصفحة حذف الإنتاج لا تزال موافقات خارجية. لا تحذف حساب وسيط أو دعم أو حسابًا بشريًا.

<a id="item-32"></a>

## 32 — الثيم والتناسق والاتجاه

**المتطلبات:** ثيم فاتح/داكن/النظام محفوظ دون سباق و RTL وتكبير نص وتناسق مكونات وأصول معتمدة.

**السابق:** جاهز وينتظر اختبار المالك على التطبيق

**المنجز الآن:** مراجعة الإغلاق والأدلة القائمة مع إعادة التراجع على الرأس الحالي؛ لا إعادة تنفيذ للميزة.

**القرار:** جاهز وينتظر اختبار المالك على Android. بعد نجاح قبول المالك وتسجيل نتيجته ينتقل إلى 1.

**الملفات المراجعة:**

- `mobile_app/lib/core/theme/theme_controller.dart`
- `mobile_app/lib/core/theme/app_theme.dart`
- `mobile_app/lib/core/widgets/app_components.dart`
- `mobile_app/lib/core/widgets/ebroker_widgets.dart`
- `mobile_app/test/owner_secondary_privacy_layout_test.dart`

**الملفات التي تغيرت الآن:**

لا ملف خاص تغيّر؛ مراجعة وحماية التنفيذ القائم.

**PRs:** [#124](https://github.com/JJalal1/real-estate-uat-backend/pull/124) [#142](https://github.com/JJalal1/real-estate-uat-backend/pull/142) [#152](https://github.com/JJalal1/real-estate-uat-backend/pull/152) [#154](https://github.com/JJalal1/real-estate-uat-backend/pull/154) [#157](https://github.com/JJalal1/real-estate-uat-backend/pull/157) [#158](https://github.com/JJalal1/real-estate-uat-backend/pull/158)

**SHAs:** historical_uat=`44a5429d91827f2da73938b71c877c38572dd663`؛ tested_head=`ca3ced8f60eed067ce1406b6661bcc583274199f`؛ merged_uat=`04b28182645af61c3c7aa11dfbfdaed4c9e86454`

**Flutter:** {"files": ["mobile_app/test/theme_preference_race_test.dart", "mobile_app/test/aqer_brand_test.dart", "mobile_app/test/secondary_admin_recovery_test.dart"], "full_regression": "PASS at current head; physical handset untested"}

**Laravel:** {"files": [], "full_regression": "430 PASS / 5091 assertions; one existing SQLite/PostGIS skip is covered in PostgreSQL job"}

**PostgreSQL و Storage:** {"evidence": "Light/dark وحجم 2.4 وخط Noto Arabic وشاشات 320×640/360×740؛ Flex/scroll/metrics/dialog/dropdown و private forms؛ 156 حالة مركزة مع header overflow72px مُصلح. API36 emulator ناجح، الهاتف باقٍ.", "current_audit": "59 migrations; RLS on all88 public tables; no direct public-client grants; private buckets; deferred tables absent"}

**CI:** PR160:19 success,0failure,1unused installer fallback skipped; see engineering receipt for job IDs

**UAT:** {"historical": "تحليل Flutter و Widget و previews اصطناعية وفحص الأصول والخطوط داخل APK؛ أربع معاينات RTL كبيرة فُحصت بصريًا.", "historical_evidence": "2026-10-26-owner-uat-v5.json + owner-preflight-v2-passed.json, source-bound, not replayed", "current_deploy": "dep-dbg0uad9fdbs73cehcp0 Live at merged UAT SHA;59migrations unchanged"}

**Android:** 1358→1359, package com.aqer.yemen.uat; API36 emulator passed; no physical-handset acceptance; Firebase client OFF

**دليل القرار:** Light/dark وحجم 2.4 وخط Noto Arabic وشاشات 320×640/360×740؛ Flex/scroll/metrics/dialog/dropdown و private forms؛ 156 حالة مركزة مع header overflow72px مُصلح. API36 emulator ناجح، الهاتف باقٍ.؛ docs/evidence/2026-10-27-engineering-ci-receipt.json

**المانع النهائي:** قبول المالك على Android فقط وفق الرحلة أدناه.

**المورد والتكلفة/التفعيل:** لا مورد إضافي يمنع تجربة المالك لهذا البند.

**اختبار ما بعد توفيره:** لا يلزم مورد؛ اختبار المالك/التراجع بحسب خطوات البند.

**اختبار المالك — الدور:** كل الأدوار

**الخطوات:** غيّر الفاتح والداكن والنظام ثم أعد الفتح؛ جرّب حجم خط 2.4 وشاشة صغيرة؛ راجع العناوين والأزرار والنوافذ والعودة و RTL.

**المتوقع:** ثيم محفوظ، قراءة واضحة، اتجاه وتنقل متسقان، ومحتوى قابل للوصول مع تكبير الخط.

**السلبي:** افتح لوحة الإدارة/التوثيق/التحديث/المناطق؛ تحقق من شريطي النظام ولوحة المفاتيح على API36 ومن جهاز أقدم.

[بوابة Storage المشتركة وحدود8/10MiB](AQER_STORAGE_ADMISSION_GATE_2026-10-27_AR.md)
