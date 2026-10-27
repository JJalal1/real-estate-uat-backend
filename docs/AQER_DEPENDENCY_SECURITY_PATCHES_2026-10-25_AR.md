# تدقيق وتصحيح الاعتماديات المثبتة — 25 أكتوبر 2026

كشف `composer audit --locked` **17 نشرة** موزعة على أربعة أسماء حزم مثبتة. لا تعني شدة النشرة وحدها إثبات استغلال التطبيق: يستخدم Aqer PostgreSQL وmiddleware bearer خاصًا، بينما تصف نشرة TokenGuard الحرجة guard مختلفًا مع إعدادات MySQL/MariaDB. لا يُستخدم هذا التفريق لاستثناء الحزمة من الإصلاح. نشرة Symfony لترويسة Cache-Control تشمل إنشاء Request قبل المصادقة، لذلك يظل تحديثها ضروريًا.

| الحزمة | المثبتة قبل العمل | النسخة المصححة المختارة | النشرات في تدقيق البداية |
|---|---|---|---:|
| laravel/framework | 13.23.0 | 13.30.0 | 3 |
| league/commonmark | 2.8.3 | 2.10.2 | 12 |
| league/flysystem | 3.35.2 | 3.35.3 | 1 |
| symfony/http-foundation | 8.1.2 | 8.1.9 | 1 |

ولدت الحزم المرشحة داخل GitHub Actions عبر Composer مع minimal-changes ودون install/scripts أو وصول UAT. حُفظ عدد الحزم ومحددات composer.json، ولم تضاف أو تزال حزمة. جدد Composer أيضًا مرجع source/dist لـphpdotenv بنفس رقم النسخة؛ أُبقي المرجع الأصلي لهذه الحزمة غير المرتبطة بالإصلاح، ليقتصر فرق package records على الحزم الأربع أعلاه. يلزم اعتماد lock النهائي نفسه بالفحص والاختبارات، ولا يكفي نجاح مرشح سابق.

أُضيفت اختبارات لمعنى Cache-Control بعد فراغ طويل دون مؤقت CPU هش، ولتقسيم الترويسة عندما يكون الفراغ نفسه separator (تصحيح Symfony اللاحق 8.1.9)، ورفض اسم Storage بترميز UTF-8 معيب دون منع الاسم العربي الصحيح، ورفض بيانات اعتماد غير نصية عبر API الحالي.

فحص Dart يستخدم الرسم المحلول الفعلي مع overrides وقفل الاعتماديات المعتمد. اجتاز **125 hosted package** استعلام OSV الأول بلا نشرة معروفة. يُرفض فشل المزود أو نقص الاستجابة أو pagination غير مكتمل، وتظل فحوص القفل الأصلية فعالة. لا يغطي هذا الاستعلام ثنائيات Flutter أو مكتبات Android الأصلية أو كل ثغرة غير منشورة.

## مصادر أولية

- [Laravel TokenGuard advisory](https://github.com/laravel/framework/security/advisories/GHSA-f9x3-7vq9-cph6).
- [Laravel debug-page advisory](https://github.com/laravel/framework/security/advisories/GHSA-jh5r-qr3c-85q8).
- [CommonMark table-parser advisory](https://github.com/thephpleague/commonmark/security/advisories/GHSA-3q6v-r5mr-hxv8).
- [Symfony header parsing advisory and follow-up](https://symfony.com/cve-2026-108082).
- [Flysystem patched normalizer](https://github.com/thephpleague/flysystem/blob/3.35.3/src/WhitespacePathNormalizer.php).
- [OSV batch protocol and pagination](https://google.github.io/osv.dev/post-v1-querybatch/).

التحديث أمن وصيانة داخل Laravel 13، وليس تبديلًا للمعمارية أو اعتمادًا للإنتاج. لا هجرة DB أو تغيير مصادقة/صلاحيات/ماليات. يلزم نشر Backend UAT بعد نجاح SHA النهائي وإثبات HTTP/Storage على النسخة المحدثة، مع بقاء منع Production والمتاجر والتكاليف دون موافقة صريحة.
