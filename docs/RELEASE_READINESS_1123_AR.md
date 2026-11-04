# جاهزية الإصدار 1123 - بوابة ما قبل UAT

## مصدر الحقيقة

- الأصل المرئي الذي وافق عليه المالك: APK1123.
- مصدر APK1123: `cdd8f8142cc2de3ee43146e84856e307908b959c`.
- فرع التدقيق والإصلاح: `work/1123-release-readiness`.
- الخادم الحي قبل rollout: commit `22a142666ad92b419eba7e41ea358b7e68199c82` على خدمة Frankfurt.
- مصدر 1123 متقدم عن الخادم الحي خطيًا ولا يفقد commits منشورة.

## تغييرات هذه البوابة

1. منع اعتماد إعلان إذا كانت أي صورة حالية له تحمل قرار مراجعة صريح `unrelated`.
   - القرار مربوط ببصمة الملف الحالية.
   - استبدال الصورة يبطل القرار القديم ولا يرثه الملف الجديد.
   - `uncertain` لا يتحول إلى رفض آلي.
2. توحيد عنوان UAT إلى Frankfurt في README.
3. جعل `render.yaml` يطابق خدمة Frankfurt، مع auto-deploy متوقف، وإيقاف seed side effects صراحة.
4. تثبيت watermark على disabled حتى rollout مقصود ومختبر.
5. توثيق متطلبات Email/WhatsApp OTP الحقيقية بدل اعتبار UI أو transport وهمي نجاحًا.
6. تشغيل بوابات Wave1/Wave2/full CI على هذا الفرع.

## فروقات البيئة التي يجب إغلاقها قبل نشر backend

### قاعدة البيانات

المطلوب قبل تشغيل Backend المرشح:

- migration إضافة `floors_count`, `units_per_floor`, `shop_openings`.
- migration إنشاء `user_messaging_blocks`.

كلاهما additive؛ لا حذف أو إعادة كتابة للبيانات التاريخية. يجب أخذ baseline counts/security state قبل التطبيق وإعادتها بعده.

### Email OTP

الكود يفشل 503 بأمان إذا لم يوجد transport حقيقي. القبول يحتاج مزودًا فعليًا واختبار inbox حقيقي. هذا ليس سببًا لإرجاع الكود إلى log mailer.

### WhatsApp OTP

UAT allowlist/test code مسار اختبار فقط. قبل Production يلزم مزود Meta الحقيقي وتعطيل أي bypass خاص بـUAT.

### Watermark

الهندسة المعتمدة موجودة ومثبتة بالبصمة. تظل `LISTING_WATERMARK_ENABLED=false` أثناء pre-rollout. بعد نشر backend ومراجعة الصور المشتقة يمكن تفعيلها بقرار منفصل ثم إعادة الاختبار.

### حذف الحساب

المتاح حاليًا هو طلب حذف عبر الدعم فقط. الحذف النهائي يبقى مفتوحًا إلى أن تعتمد سياسة الاحتفاظ والعلاقات المالية/التدقيقية؛ لا يوصف بأنه مكتمل.

## أداء UAT

لوحظ في Render وصول Apache إلى `MaxRequestWorkers 12` في أكثر من وقت، بدون 5xx مؤكدة في نافذة الفحص وبدون دليل على استنفاد Supabase pool. لا نرفع العمال عشوائيًا. بعد rollout نعيد نفس load/latency checks ونحدد إن كان السبب burst أو endpoint بطيئًا أو cold start أو اتصال قاعدة.

## ترتيب rollout المقترح بعد نجاح CI

1. تثبيت SHA المرشح وعدم إضافة تغييرات جديدة.
2. baseline قراءة فقط لعدد الجداول الحساسة، migrations، storage، jobs، وأمان RLS/grants.
3. تطبيق migrations المطلوبة فقط والتحقق من schema/constraints/RLS.
4. نشر backend من SHA المرشح يدويًا إلى Frankfurt UAT.
5. انتظار deploy حتى `live` ثم فحص `/api/health`.
6. smoke/API tests للبحث، العقارات، auth، media، review، block/report.
7. فحص logs/metrics وSupabase connections بعد الاختبار.
8. تشغيل اختبار الهاتف للدفعة الأولى والثانية.
9. لا merge ولا Production قبل إغلاق النتائج.

## ما لا تعتبره هذه البوابة نجاحًا

- نجاح CI لا يساوي نجاح الهاتف.
- وجود endpoint لا يساوي وجود migration الحي.
- ظهور شاشة Email OTP لا يساوي وصول بريد حقيقي.
- وجود watermark assets لا يساوي تفعيلها على الخادم.
- status=live في Render لا يساوي قبول المنتج بدون smoke/log/database checks.
