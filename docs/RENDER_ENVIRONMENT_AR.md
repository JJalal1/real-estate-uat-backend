# متغيرات Render

`render.yaml` يعرّف القيم غير السرية. أدخل القيم التالية من Dashboard فقط عندما يطلبها Render:

- `APP_KEY` — مفتاح Laravel صالح بصيغة `base64:...`
- `DB_URL` — Supabase Session Pooler connection string (port 5432)
- `SUPABASE_URL` — Project URL
- `SUPABASE_STORAGE_SERVER_KEY` — server-side secret key فقط
- `UAT_TEST_OTP_CODE` — كود UAT من 6 أرقام
- `UAT_TEST_PHONE_NUMBERS` — أرقام الاختبار المسموح لها فقط

لا ترسل هذه القيم في المحادثة ولا تضعها في GitHub.
