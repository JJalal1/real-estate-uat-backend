# مصفوفة اعتماد القالب

هذه مصفوفة العمل المقترحة بعد فحص الحزمة المرفقة فعليًا. الإصدار المثبت من `app/pubspec.yaml` هو 1.8.0+88. مسارات القالب أدناه هي المسارات الموحدة بعد استرجاع المرجع المنقح من GitHub واستخراجه؛ بصماتها في `ebroker-audit-summary.json`. الفرع `reference/ebroker-1.8.0` مثبت عند `425f019070db73253ff77181c77623d28225cc25`، وقد تحققت الملفات الـ2005 وبصمات ملفات المصدر المختارة الـ21. إثبات الاسترجاع في `TEMPLATE_REFERENCE_VERIFICATION.json`، و[مرجع القالب المثبت](https://github.com/JJalal1/real-estate-uat-backend/tree/425f019070db73253ff77181c77623d28225cc25) يبقى للفحص دون دمج شجرته في النسخة الثالثة.

## ربط المكونات بالملفات

| المرحلة | مصدر eBroker المفحوص | هدف مشروعنا | قيد النقل |
|---|---|---|---|
| 1 | `app/lib/ui/theme/theme.dart` | `mobile_app/lib/core/theme/` | استخراج التكوين البصري؛ إبقاء NotoSansArabic وRTL وFlutter 3.27.3 |
| 1 | `app/lib/ui/screens/home/home_screen.dart` و`home_sections.dart` | `mobile_app/lib/features/discovery/presentation/` و`router/app_router.dart` | Home تعرض بياناتنا الحالية فقط؛ لا جلب Cubits أو إعلانات أو أقسام جديدة |
| 2 | `app/lib/ui/screens/home/widgets/property_card_big.dart` و`property_horizontal_card.dart` | بطاقات العرض الحالية ضمن discovery والمكونات المشتركة | إبقاء نماذج Property وRiverpod والصلاحيات وحالات الإتاحة |
| 2 | `app/lib/ui/screens/proprties/property_details/property_details_screen.dart` ومعرض `widgets/property_gallery.dart` | شاشة تفاصيل العقار الحالية | نقل التركيب البصري مع بقاء إجراءات الأصل؛ ملف القالب يعتمد على appointment وsubscription وAdMob |
| 2 | `app/lib/ui/screens/filter_screen.dart` و`home/search_screen.dart` و`favorites_screen.dart` | البحث والفلاتر والمفضلة الأصلية | API والبحث وMapLibre والمفضلة الخادمية الحالية تبقى مرجع السلوك |
| 3 | `app/lib/ui/screens/auth/login_screen.dart` و`profile/profile_screen.dart` | حسابنا ودخولنا الحاليان | تصميم فقط؛ لا Firebase Auth أو Google/Apple sign-in أو Hive |
| 3 | `app/lib/ui/screens/proprties/add_property/add_property_screen.dart` ومجلد `steps/` | محرر الإعلان الحالي | إبقاء حفظ المسودة والمعاينة والإرسال للمراجعة ومتطلبات KYC والأهلية |
| 4 | `app/lib/ui/screens/chat/chat_screen.dart` و`chat/widgets/chat_contact_actions.dart` | واجهة المحادثة الأصلية | إبقاء محادثة العقار الواحدة وحالات المعاينة والقبول بين الأطراف |
| 4 | `app/lib/ui/screens/proprties/widgets/property_contact_buttons.dart` | إجراءات التواصل من محادثتنا | لا نسخ الاتصال المباشر الموجود في القالب؛ يلزم مسار API تسجيل الاتصال والإشعار ومتابعة الدعم قبل tel |
| 5 | `admin/resources/views/` وأنماط عرض القالب المناسبة | واجهات الدعم والإدارة الأصلية | نمط بصري فقط عند الملاءمة؛ shared queue/claim وLaravel authorization الأصليان حاكمان |

## توافق البيئة

القالب يعلن Dart `^3.10.0` ويستخدم Bloc/Cubit وFirebase/Hive ومكتبات خرائط واشتراكات وإعلانات. مشروعنا يبقى على Flutter 3.27.3 وRiverpod وgo_router وMapLibre وعقود Laravel/PostgreSQL الحالية. تعتمد الدفعات على إعادة بناء التصميم داخل هذه البيئة؛ لا ينسخ `pubspec.yaml` أو `pubspec.lock` أو طبقة البيانات أو Auth أو الإعدادات من القالب. تبقى مكونات `material_ui` و`cupertino_ui` المعلنة بـ`any` في حزمة القالب مرجعًا للفحص؛ لا تضاف إلى مشروعنا ضمن التجهيز.

الثيم المفحوص يستخدم لونًا رئيسيًا مساعدًا `#087C7C` مع خلفيات فاتحة `#FAFAFA` و`#FFFFFF`، وخط Manrope في حزمة القالب. هذه معلومات مصدر للمراجعة البصرية؛ الهوية والألوان النهائية تحتاج قبول صاحب المشروع، والخط العربي الحالي يبقى ضمن القيود.

## حدود اعتماد المنظومات

| الجزء | ما يؤخذ من eBroker | ما يبقى من مشروعنا | المرحلة |
|---|---|---|---|
| النظام البصري | لغة التصميم والتدرج والمسافات والألوان والمكونات المناسبة | الهوية العربية وRTL وبيئة Flutter الأصلية | 1 |
| Home والتنقل | ترتيب Home والعرض المناسب | مسارات الأصل ومساحات الأدوار وauth wrappers | 1 |
| البطاقات والقوائم والتفاصيل | تركيب المكونات والعرض والمعرض | Property models وAPI والخصوصية وحالات الإتاحة | 2 |
| البحث والفلاتر والخريطة | التصميم فقط | محرك البحث والفلاتر وMapLibre وPostGIS الحالي | 2 |
| المفضلة والمقارنة والبحث المحفوظ | المظهر المناسب | سلوك الأصل وبيانات الحساب والخادم | 2 |
| الدخول والحساب | واجهات مناسبة قابلة لإعادة الربط | Auth الحالي والتحقق والجلسات؛ لا Firebase Auth أو منظومة دخول بديلة بسبب القالب | 3 |
| KYC والإعلان | تصميم الحقول والخطوات دون فرض تسلسل القالب | أدوارنا وأهلية النشر وKYC والمسودة والمراجعة والتصحيح | 3 |
| الرسائل والاتصال | مظهر المحادثة | المحادثة أولًا ثم API تسجيل الاتصال ثم tel؛ لا اتصال مباشر يتجاوزها | 4 |
| المعاينات والعقود والإشعارات | مكونات عرض مناسبة | آليات الأطراف والحالات وdeep links وعقود API الأصلية | 4 |
| الدعم والإدارة والخدمات | أنماط عرض مناسبة أو تصميم متناسق مخصص | shared queue/claim وصلاحيات المدير والدعم والعمليات الأصلية | 5 |
| Backend/MySQL/installer/license activation | يفحص سلوكها ويوثق؛ لا تشغل ولا تتبنى | Laravel وPostgreSQL/Supabase الحالي | مرجع فقط |
| Next.js website | يحتفظ مرجعًا منفصلًا | ليس جزءًا من تلبيس تطبيق Flutter الحالي | اختيار لاحق |
| ميزات إضافية أو monetization | لا تضاف ضمن المطابقة | تختار واحدة واحدة بعد Gate والتنظيف ومراجعة الرخصة عند مرحلتها | لاحقًا |

لكل شاشة منقولة نسجل في PR: ملف المصدر المرجعي وبصمته، ملف هدف UI، عمليات الشاشة قبل النقل وبعده، IDs بنود المطابقة، ونتائج الاختبار وcommit المرجع. لا ينقل repository أو provider أو model من القالب لمجرد أن مكون العرض يعتمد عليه.
