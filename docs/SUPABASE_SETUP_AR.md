# إعداد Supabase UAT

1. افتح مشروع Supabase الخاص بـ UAT.
2. من Database > Extensions فعّل `postgis` واختر إنشاء schema باسم `gis`.
3. من Storage أنشئ bucket خاص (Private) باسم `real-estate-uat`.
4. من Connect انسخ **Session pooler** connection string على المنفذ `5432` لاستخدامه لاحقًا كـ `DB_URL` في Render.
5. من Settings > API Keys استخدم server-side Secret key من نوع `sb_secret_...` لاحقًا كـ `SUPABASE_STORAGE_SERVER_KEY` داخل Render فقط.

لا تضع أي قيمة سرية داخل GitHub أو التطبيق المحمول.
