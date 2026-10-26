# تشغيل إشعارات UAT الآمن — 27 أكتوبر 2026

ملف Android الحقيقي المرفق فُحص محليًا: مشروع `aqer-yemen`، sender `982331876719`، وحزمة `com.aqer.yemen.uat`، وعميل واحد مطابق. أُنشئ ملف properties خارج Git بصلاحية600، ولم تطبع API key أو Firebase App ID أو بيانات اعتماد. هذا يصحح فقرة «لم يظهر الملف» في وثيقة الاستلام المؤرخة26 أكتوبر، ولا يثبت وصول إشعار.

يستخدم التطبيق SDK الأصلي نفسه؛ لا FlutterFire ولا Google Services Plugin مكرر. CI يستورد `AQER_UAT_GOOGLE_SERVICES_JSON_BASE64` ويثبت وجود قيم العميل في DEX دون طباعتها، مع بصمة إعداد آمنة. إذا غاب السر يبقى `client_configured=false` وpush OFF. هذا هو حال البناء الجاري حتى يوفر السر في GitHub Actions؛ لا يجوز وصف APK الناتجة بأنها مربوطة بالملف الحقيقي. موصل GitHub لا يكتب Secrets، ومحاولة صفحة الإعدادات البديلة حُجبت بالشبكة؛ لم نحفظ سرًا. لا تكشف المفتاح في تعليق أو تقرير لحل ذلك.

## ما تحقق هندسيًا

- Laravel يرسل data-only allowlist دون title/body أو بيانات حساب خاصة، بعمر300 ثانية ومحدد package. قبول FCM طلبًا ليس إثبات تسليم هاتف.
- التسجيل يتطلب جلسة وموافقة؛ receipt يربط user_id ورمز الجهاز؛ Android يفحص recipient/token fingerprint/session generation قبل العرض وفتح المسار. تجديد الرمز يبطل الربط القديم حتى إقرار الخادم.
- الخروج وبدء حذف الجلسة يسحبان الموافقة والتنبيهات المحلية قبل انتظار الشبكة. callbacks والتسجيلات المتأخرة لا تستخدم bearer الحساب الجديد. لا تُحفظ قيمة bearer أو FCM token الخام في PushSessionState.
- الرسالة الظاهرة عامة، والوجهة allowlist وتُفحص ثانية عند النقر. الملفات الخاصة تُقرأ بترخيص Laravel الحالي. نفس الحساب بجلسة جديدة يحتاج تسجيلًا وموافقة مناسبين ولا يرث generation قديمًا.
- Job على `database`/`push` مستقل عن sync Web، timeout30s، retries3 وbackoff محدود وRetry-After، تعطيل registration منتهية، ومفاتيح OAuth خارج APK. عامل nonroot بلا FFmpeg أو migrations.

نتائج CI والمحاكي تُوثق في الإيصال النهائي. اختبارات Android ذات envelopes اصطناعية ليست FCM حقيقيًا أو اختبار هاتف المالك.

## المتطلبات الخارجية والتفعيل

1. أضف الملف المرفق نفسه إلى GitHub Actions Secret بالاسم أعلاه في قناة إدارية مصادق عليها، دون نشره. أعد بناء زوج A/B من نفس SHA وبنفس مفتاح UAT وتحقق أن `firebase_client.configured=true` وبصمتهما واحدة. النسخة القديمة1340 وحزمة com.example لا تدخل هذا الإثبات.
2. اعتماد خادمي مخصص UAT من Google IAM بالصلاحية اللازمة للإرسال إلى المشروع المعتمد، دون Owner/Editor عام إذا أمكن تجنبه. FCM على Spark لا يحتاج شراء Blaze. أوقف أي اعتماد Production حتى اعتماد هويته.
3. احفظ Service Account JSON في Render Secret File باسم `fcm-uat-service-account.json` للعامل فقط، واضبط `FCM_SERVICE_ACCOUNT_FILE=/etc/secrets/fcm-uat-service-account.json`. لا تجمعه مع المتغير BASE64. تحقق من القراءة كـwww-data؛ لا تطبعه أو تنسخه في image. المصدر الرسمي لملفات Render السرية: https://render.com/docs/configure-environment-variables .
4. عامل دائم مستقل يحتاج قرار مورد؛ يمكن اختبار نافذة قصيرة مجانية بعامل محدود على جهاز/CI موثوق بعد توفير الاعتمادات والموافقة، دون اعتباره تشغيلًا دائمًا. لا يتم إنشاؤه تلقائيًا ولا شراء خطة بهذه الوثيقة.
5. على العامل: APP_ENV=staging، FCM_PROJECT_ID=aqer-yemen، FCM_ANDROID_PACKAGE=com.aqer.yemen.uat، PUSH_QUEUE_CONNECTION=database، PUSH_QUEUE=push، PUSH_NOTIFICATIONS_ENABLED=true. شارك APP_KEY وDB_URL الآمنين من بيئة UAT فقط. `php artisan push:readiness` يجب أن ينجح دون إرسال. شغّل Dockerfile.queue-worker وفق entrypoint المثبت؛ ابدأ concurrency=1.
6. بعد تأكد العامل: فعّل dispatch على Web لنفس queue؛ لا تغيّر QUEUE_CONNECTION العام من sync بلا دراسة بقية وظائف المنصة. لا يحتاج Web مفتاح FCM الخاص إذا لم يرسل بنفسه.

## اختبار بعد التفعيل

على هاتفين بحسابين اصطناعيين موجودين: إذن denied/permanent denied/allow؛ foreground/background/cold start؛ رسالة ومراجعة وحدث مسموح بحسب الدور؛ نقر ونقل إلى auth ثم الوجهة؛ تسجيل جديد وتجديد token؛ logout ثم login لحساب آخر؛ callback متأخر ورسالة قديمة ومكرر وroute خبيث؛ سحب consent محليًا أثناء انقطاع الشبكة؛ حذف الحساب وإبطال الرموز. سجل هوية APK والشهادة وSHA وتوقيت إنشاء الحدث وقبول المزود واستلام الهاتف منفصلة، بلا محتوى خاص أو tokens. اختبر force-stop وDoze كقيود تسليم Android دون ادعاء ضمان فوري. لا تستخدم FCM للإعلانات المخفية أو الرسائل الخاصة للمستخدم السابق.

## المراقبة والتراجع

راقب `push.provider_accepted` و`push.provider_rejected` و`push.retry_scheduled` و`push.registration_expired` و`push.exhausted` دون payload/token. فشل دائم أو أي exhausted يحتاج تنبيهًا للمشغّل؛ backlog أقدم من120s أو زيادة مستمرة عن100 job لمدة5 دقائق حدود تشخيص أولية وليست SLO مقبولًا. استخدم `php artisan queue:monitor database:push --max=100` مع مستمع/جهة إنذار معتمدة عند تجهيز المراقبة؛ لا يكفي تشغيل الأمر بلا استقبال الحدث. تتبع jobs(queue=push)، failed_jobs، CPU/RSS/connection count، وشبكة OAuth/FCM. لا تُعد provider_accepted مرادفًا delivered.

لإيقاف الإرسال: أغلق PUSH_NOTIFICATIONS_ENABLED على Web والعامل ثم أعد نشر الإعدادات أو أوقف العامل؛ احتفظ بإشعارات in-app. لا `queue:flush` عام ولا `queue:retry all`. عالج job محددة بعد تأكيد أن الحساب/الجهاز ما زالا صالحين؛ TTL300s يحد stale delivery. عند سر مكشوف ألغِه لدى Google ودوّره في مدير الأسرار، ثم اختبر readiness وcanary. Production Firebase/package/domain/signing/OTP جميعها مستقلة ومعطلة حتى اعتمادها.

المانع النهائي لـ#8 يجب أن يذكر سر البناء الحقيقي، واعتماد الإرسال الخادمي ونافذة عامل، ثم اختبار التسليم على الهاتف. لا يُختزل في «الكود ناجح إذًا وصل الإشعار».
