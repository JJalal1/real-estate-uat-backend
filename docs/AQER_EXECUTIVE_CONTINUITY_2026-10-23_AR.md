# عقار | Aqer — تسليم تنفيذي محدث (23 أكتوبر 2026، توقيت اليمن)

> هذا سجل استئناف حي على فرع الفيديو، وليس شهادة إطلاق ولا إذن شراء أو نشر Production. راجع GitHub وRender وSupabase مجددًا قبل أي تغيير؛ الحالة الحية تتقدم على هذا السجل.

## النقطة التي تم الوصول إليها
- المستودع: `JJalal1/real-estate-uat-backend`، فرع UAT: `work/wave2-review-current`.
- PR #112: **merged**، merge SHA `342300fe2c20265751b2b28e2090326332c3c9f7`. تمت مطابقة البصمات SHA لملفات التخزين الخمسة المشتركة مع #111؛ لم يحدث فقد للكود.
- خدمة UAT فقط: `real-estate-uat-api-frankfurt`، Render service `srv-dahj3vlg1s2s73bdqhtg`، workspace `tea-d4v0q98gjchc73cistt0`، خطة Free، autoDeploy OFF. آخر نشر مؤكد: `dep-dbda8o4s728c73b7b4h0` **live** على `342300fe2c20265751b2b28e2090326332c3c9f7`.
- UAT private storage canary **passed LIVE**: سجل Render في `2026-10-23T00:03:05Z`: `Private UAT video storage canary passed: streamed upload, exact range and full download.` تم الاستعلام من `storage.objects` عن `uat-health/video-range-%` والعدد **0**. أعيد علم `UAT_VIDEO_STORAGE_PROBE_ON_STARTUP=false` ونشر الاستعادة live. لا تعيد canary بلا سبب.
- Supabase UAT project: `ipxsgxsqzthpgthwvdno`، تنظيم Free، PostgreSQL 17، 59 Laravel migrations، `listing_videos` و`listing_video_worker_health` غير موجودين، bucket `real-estate-uat` خاص، `failed_jobs=0`، `video jobs=0`. لحظة الفحص: 14 PostgreSQL sessions، واحدة active، حجم قاعدة 32MB؛ هذا قياس لحظي وليس تقدير ذروة.
- PR #111 الفيديو Draft/Open. كان الرأس `d7efa9ab2ec3a27b25a72f65549ca3102cb8fea4` وجميع **6/6** GitHub checks **success** (آخرها Flutter 2026-10-23T00:07:40Z). الإصلاح اللاحق على فرع الفيديو يحتاج CI جديدًا؛ **لا تعدّه أخضر حتى يؤكد HEAD الجديد**.
- أضيف اختبار تراجع لانقطاع العامل أثناء تنزيل الأصل: التأكد من `failed` وتنظيف مشتقات متروكة، ثم إعادة التسليم الآمنة دون نسخ مكرر. تعديلات الاختبار في `backend-api-runtime/tests/Feature/ListingVideoFullCycleTest.php`: `7bc2cf90d6a848955dcdb51d47ced13603b077f6` ثم تصحيح PHP namespace `67d14d7627f2ccd8d8520f14483435085d511f67`. افحص الفحوص على رأس الفرع بدل افتراض نجاحها.
- خدمة FFmpeg **لم تنشأ**، ولا يُسمح بتشغيله داخل Apache Free. Dockerfile.worker نجح build وpcntl/non-root في CI؛ هذا لا يثبت تشغيل worker/live memory.
- Laravel migration الفيديو جاهزة في الكود فقط `2026_10_23_000100_create_listing_videos_table.php`. **لم تطبّق على UAT**.
- لم يُفعل `LISTING_VIDEO_UPLOADS_ENABLED` أو `LISTING_VIDEO_PROCESSING_ENABLED` في UAT؛ التطبيق لا يزال OFF افتراضيًا.
- مصفوفة البنود الـ32 عند `docs/APPROVED_32_RELEASE_MATRIX_AR.md` تاريخية وتحتاج تحديث أدلة لا إعلان إغلاق. فجوات #1/#11/#12/#16 و#109 أداء. لا يوجد قبول الهاتف المجمع بعد.

## حاجز جديد مهم ثبت بمراجع المزود
- Supabase UAT organization على **Free**. وثائق Supabase الرسمية تذكر أن **النسخ اليومية التلقائية ليست متاحة للمشروع المجاني**؛ يلزم `pg_dump` آمن وحفظ خارج الموقع وإثبات استعادة قبل أي migration، أو اعتماد ترقية صريحة. لا تتعامل مع حالة `ACTIVE_HEALTHY` كنسخة احتياطية.
- تكلفة Render المرجعية الرسمية: Starter `0.5 vCPU/512 MB` = **$7/شهر**؛ Standard `1 vCPU/2 GB` = **$25/شهر** في مقارنتهم الرسمية، قبل أي تكلفة أخرى. لم يُشتر أيّ منهما. لا توصي بحجز عامل 512MB لترميز فيديوهات حتى يجتاز قياس CPU/RSS/وقت FFmpeg على عينات حدود 50MiB/90s وفي ظروف DB sessions. راجع أسعار workspace وعرض Render الحالي قبل الموافقة.
- Redis/Key Value ليس شرطًا في هذا التصميم لأن `database_video` يستخدم PostgreSQL `jobs` مع `retry_after=660`، وقت `--timeout=540` وخيط عامل واحد. يجب إثبات الاسترداد الحقيقي من SIGTERM/KILL والتكرار ونبض `720s` على UAT.
- اختبار CI `ListingVideoFullCycleTest` يختصر تأكيد الموظف بتحديث نموذج بيانات في fixture؛ هذا ليس بديلًا عن مسار UAT بشخصية موظف مع صلاحيات فعلية.

## مهام المتابعة بلا تكرار مراحل ناجحة
1. افحص أحدث SHA على PR #111 وcheck-runs؛ عند الفشل اقرأ اسم الـJob والـLogs وأصلح السبب الحقيقي.
2. تأكد من قيود Render على خطط background workers الحالية، والمقاييس الحقيقية المطلوبة، وخطة أسرار العامل من Render دون نسخ كلمات مرور في Git.
3. جهز نسخة قاعدة آمنة مُختبرة الاستعادة (دون تصدير بيانات الأشخاص إلى Git)، وتحقق من إمكان التنفيذ عبر أدوات متصلة؛ لا تطبق migration قبلها.
4. بعد موافقة المالك على التكلفة المحددة، أنشئ worker مستقل في Frankfurt بموارد محسوبة و`autoDeploy=no`، لا داخل web Free. تأكد أن الحاوية تستخدم `backend-api-runtime/Dockerfile.video-worker`، queue `database_video/video`، وأنه لا يوجد public ingress.
5. بعد backup ثم نشر backend/video schema مع flags OFF، طبق migration وراجع RLS/revokes/constraints.
6. فعل heartbeat للعامل، راقب DB ومنع 503 عند توقفه؛ ثم افتح الفيديو UAT فقط وقم بدورة الاصطناعي الحقيقية upload→FFmpeg→poster→staff confirm→public Range→delete؛ اختبر الانقطاع وإعادة المحاولة. حافظ على Production غير ممسوس.
7. أغلق فجوات البنود الـ32 باختبارات وتحديث المصفوفة؛ عالج #109 بمقاييس p50/p95 وDB/CPU. ثم UAT Android واحدة محمية وبصمة SHA256، قبول هاتف بشري مرة واحدة، RC، Production منفصلة، متجر Play؛ iOS فقط إن طُلب.

## قواعد ثابتة
لا خدمات مدفوعة أو تغييرات Production/Package ID/Signing دون موافقة صريحة ومبلغ. لا إعلان إغلاق بند من نجاح Unit/CI وحده. لا تمرير private URLs أو API keys للعملاء ولا فتح Supabase Data API. أحفظ حالة جديدة في كل تسليم بعد أي تغيير كبير.

