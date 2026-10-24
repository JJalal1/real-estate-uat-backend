# عقار — سجل التنفيذ المباشر 25 أكتوبر 2026

## الاستلام والتحقق
- مصدر الاستلام الحي `fc062313847c78181a2068f214b921546c05492a`، الفرع `work/wave2-review-current`؛ CI: 11 success وواحد skipped لنقل installer اختياري، وليس اختبارًا فاشلًا.
- قورنت تغييرات PR132/133/134 مع آخر الفرع، ولا تداخل مع PR131 أو بعضها. روجعت عقود Push/Deep Link والتعافي من فشل الملفات.
- PR132 merged `9eec0d85af68c97ab42db39fc2f75c483d4881cd`؛ PR133 merged `3e6cc1e98b0f488fe25995a85c5670b19f5c7106`؛ PR134 merged `a07f2d786bc5e4a0e3d15191ba66a489451a30a5`؛ PR136 merged `766d3b14b9bd2578f53bd20cfd79c4660899d419`.
- لكل PR132/133/134: 11 checks ناجحة وواحد skipped على رأسه قبل الدمج. PR136 وثائق فقط وفحصه ناجح. CI على SHA التجميع مستقل ويجب التحقق منه؛ لا قبول Android فعلي بعد.
- Render: النشر `dep-dbe71e3rjlhs73elu3cg` live على `ca184fc0c1ae67443786a72a32911b80d1ed5197`، Free Frankfurt، instance واحدة، autoDeploy OFF. لم يُعد نشر Flutter/Docs.
- Supabase: 59 migrations؛ جدول `listing_image_upload_intents` غائب؛ 88/88 جدول public مع RLS؛ صفر منح anon/authenticated مباشرة؛ صفر قيود غير validated؛ bucket `real-estate-uat` خاص. Advisors: 88 RLS-no-policy INFO و161 unused-index INFO. لا تغييرات DB/Storage.
- قياسات Render الأخيرة: http_latency/http_request_count بلا عينات؛ لا اعتماد p95. سجل تشبع Apache حديث في 2026-10-24T22:41:41Z؛ Issue109 مفتوحة.
- المواصفتان الأصليتان غير موجودتين في شجرة GitHub الكاملة أو البحث باسميهما في Drive؛ تعتمد المراجعة المصفوفة الحالية دون ادعاء المطابقة الحرفية.

## إصلاح PR122 دون إضعاف منع التكرار
- الفشل القديم على `c9d5ab454cde0b9db0b8695f7eaab803a375f161` كان في `duplicate_same_physical_asset` ضمن HTTP فعلي على PostgreSQL.
- السبب المثبت في المصدر: `ListingReviewController::data` يعيد `data.property_asset.id`، بينما الاختبار قرأ `data.property_asset_id`. استجابة المعلن تستخدم FK المسطح.
- صُحح مسار القراءة، وأضيف شرط ID موجب حتى لا ينجح تطابق null مع null. بقي تحقق تطابق الهوية ورفض submit بـ409 ورسالة already published، دون تغيير منطق المنتج أو قواعد النشر.
- وُفّق PR122 مع SHA التجميع أعلاه؛ مقارنة e7aad95b…766d3b14 أثبتت أن التغييرات اللاحقة Flutter/Docs فقط ولا تتداخل مع ملفات PR122.
- التنفيذ والاختبارات التالية قيد التحقق؛ لا يُدّعى نجاحها قبل CI جديد، ولا UAT/Android قبل أدلة فعلية.

## بوابات باقية
#3/#21 تكلفة ومراجعة فيديو، #11 نسخة DB مشفرة كاملة واستعادة مستقلة قبل هجرته، #20 OFF، FCM والدومين والتوقيع والمتجر وAndroid المجمع والأداء109. لا Production أو موارد مدفوعة أو تغيير مدمر.

## عطل إضافي مثبت في ترتيب المصادقة وتحديد المعدل
- CI عند `418d7c9745da66d88a8f021f5919447dc107fe30`: تطابق الهوية و409 ورسالة منع النشر نجحت، ثم أعاد حذف الحساب الصحيح 429 بعد حساب موظف ومحاولة تأكيد غير صحيحة من المعلن، مع cleanup ناجح.
- Laravel المثبت `v13.23.0` عند `92a707229148e57f08a249211c8a5a194159c619`: ترتيب middleware يعتمد contract `AuthenticatesRequests` قبل ThrottleRequests. وسيط `auth.api` المخصص لم يكن يعلنه؛ فاستُخدم مفتاح IP المجهول بدل حساب المستخدم، ما يحرم حسابات أخرى خلف نفس proxy من حصتها.
- التصحيح يعلن contract الرسمي فقط. حدود الحذف 2/60 دقيقة وعمليات الدخول 6/دقيقة وغيرها لم تتغير، ولا ثقة جديدة في X-Forwarded-For.
- اختبار تراجع جديد يثبت 429 للحساب نفسه مع تبديل token/IP، عزل حساب آخر وحذفه فعليًا، عدم استهلاك الطلب المجهول لحصة الحساب، وبقاء حد الدخول العام محميًا من spoofed forwarded IP. سيعمل على SQLite وPostgreSQL مع الرحلة الحقيقية كاملة.
- baseline SQLite: marketplace 41→15 استعلامًا وبصمة semantic متطابقة؛ nearby 64→8. هذه قياسات قاعدة معزولة، لا سعة إنتاج. عينة UAT 20/مسار، concurrency≤3: health p95 1040.5ms، thumb 2424.1ms، marketplace 2436.5ms، أخطاء0. النشر ما زال ca184fc0؛ هذه عينة قبل نشر الإصلاح.
