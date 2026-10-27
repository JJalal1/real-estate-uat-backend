# بيئة Render المعتمدة - Frankfurt UAT

هذه الوثيقة تصف بيئة UAT الحقيقية التي يجب أن تطابق مصدر الإصدار قبل قبول أي APK.

## الخدمة المعتمدة

- الخدمة: `real-estate-uat-api-frankfurt`
- المنطقة: `frankfurt`
- Health check: `/api/health`
- API المستخدم في APK UAT: `https://real-estate-uat-api-frankfurt.onrender.com/api`
- النشر التلقائي يبقى متوقفًا أثناء مرحلة الاعتماد؛ كل نشر يجب أن يكون لمصدر SHA محدد ومختبر.

## أسرار الاتصال الأساسية

أدخل القيم السرية في Render فقط، ولا تضعها في GitHub أو التقارير:

- `APP_KEY` - مفتاح Laravel صالح.
- `DB_URL` - Supabase Session Pooler connection string.
- `SUPABASE_URL` - عنوان مشروع Frankfurt.
- `SUPABASE_STORAGE_SERVER_KEY` - مفتاح خادمي فقط.
- `UAT_TEST_OTP_CODE` و`UAT_TEST_PHONE_NUMBERS` - للاختبارات المسموح بها على UAT فقط.

## إعدادات قاعدة البيانات والتجارب

القيم المستهدفة في UAT:

- `DB_CONNECTION=pgsql`
- `DB_SSLMODE=require`
- `DB_SEARCH_PATH=public,gis,extensions`
- `DB_PERSISTENT=false`
- `UAT_DEMO_SEED_ENABLED=false`
- `UAT_CITY_DEMO_SEED_ENABLED=false`
- `UAT_WAVE3_FIXTURES_ENABLED=false`

لا يعتمد الإصدار على إعادة زرع بيانات أثناء النشر. أي fixtures أو seed إضافي يحتاج قرارًا منفصلًا.

`UAT_RUN_MIGRATIONS` موجود في مسار التشغيل، لكن إصدارًا مرشحًا لا يعتبر جاهزًا لمجرد أن entrypoint يستطيع تشغيل migrations. قبل النشر نراجع migrations المطلوبة ونطبقها/نتحقق منها بخطة rollout موثقة.

## البريد الإلكتروني الحقيقي

مسار Email OTP يفشل بأمان إذا لم يكن مزود بريد حقيقي مهيأ. لا يعتبر تسجيل الدخول بالبريد مقبولًا حتى:

1. اختيار transport حقيقي مثل SMTP/مزود متوافق.
2. ضبط `MAIL_MAILER` ومتغيرات المزود السرية في Render.
3. ضبط `MAIL_FROM_ADDRESS` و`MAIL_FROM_NAME` بعنوان وهوية مرسل حقيقيين.
4. اختبار وصول OTP إلى صندوق بريد حقيقي وعدم ظهوره في logs أو API.
5. اختبار الفشل وRate Limit وإعادة الطلب.

لا تستخدم `log` أو `array` كبديل عن التسليم الحقيقي خارج local/testing.

## واتساب OTP

الأرقام المسموح بها في UAT يمكن أن تستخدم Test OTP المحدود والمسموح به. أما التحقق الحقيقي فيحتاج إعداد Meta WhatsApp:

- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_ACCESS_TOKEN`
- `WHATSAPP_AUTH_TEMPLATE`
- `WHATSAPP_AUTH_LOCALE`

Test OTP يجب أن يبقى خاصًا بـUAT ولا يستخدم في Production.

## صور العقارات والعلامة المائية

- `LISTING_WATERMARK_ENABLED=false` حتى اعتماد rollout واختبار مشتقات الصور على UAT.
- `LISTING_WATERMARK_APPROVED_SHA256=bf7611483e0689ad9ccd73458442745ff9fc4c91a07d60cf2c3521be90698b6e`
- الأصل الخاص لا يعدل؛ العلامة توضع على مشتقات العرض فقط.
- تفعيل العلامة لا يعني إعادة معالجة الصور التاريخية تلقائيًا.

## ملاحظة Blueprint

`render.yaml` في هذا الفرع يمثل خدمة Frankfurt الحالية ويجب مراجعته قبل أي Blueprint sync. لا تعمل Sync من ملف قديم أو من فرع آخر؛ اسم الخدمة والمنطقة والفرع يجب أن يطابقوا الخدمة المقصودة حتى لا تنشأ خدمة ثانية أو يتغير مصدر النشر.

أي تغيير ENV أو Blueprint أو deploy يحتاج تحققًا بعده من Health/API/DB والـlogs، ولا يعتبر حفظ الإعداد مساويًا لنجاح النشر.
