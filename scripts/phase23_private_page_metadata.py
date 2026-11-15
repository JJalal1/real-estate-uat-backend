"""Numeric-only observations for the opt-in read-only private-page target."""
import json

MARKER = 'AQER_PHASE23_PRIVATE_PAGES_READ_ONLY_V1'
META = frozenset(('v','actor','epoch','events','errors','writes','pushCleanup'))
EVENT = frozenset(('seq','surface','actor','epoch','page','original','size','phase',
                   'count','last','total','totalKnown','duplicate','changed'))
CONTROLS = frozenset(('PC controls','PC hide','PC home','PC listings','PC favorites',
    'PC availability','PC customers','PC verification','PC messages','PC support','PC light','PC dark',MARKER))
LABELS = frozenset(('حسابي','العقارات','المفضلة','إعلاناتي','عقاراتي','الرسائل',
    'رجوع','تحديث','إعادة المحاولة','تحميل المزيد','المزيد من الإعلانات',
    'المزيد من المفضلة','المزيد من المحادثات','المزيد من طلبات التحقق',
    'المزيد من المهام','المزيد من الطلبات','المزيد من البلاغات','المزيد من العملاء','المزيد من الحالات',
    'لا توجد إعلانات بعد','لا توجد عقارات محفوظة','لا توجد طلبات بهذه الفلاتر.',
    'لا توجد عملاء في هذه القائمة بعد. ستظهر هنا المحادثات المرتبطة بإعلاناتك.',
    'جارٍ التحميل...','جارٍ تحميل المحتوى','جارٍ تحديث المحتوى',
    'تعذر الاتصال بالخادم. تأكد من تشغيل الخدمة واتصال الهاتف ثم حاول مرة أخرى.',
    'استغرق الاتصال وقتاً أطول من المتوقع. حاول مرة أخرى.',
    'الخادم غير متاح مؤقتاً. حاول مرة أخرى بعد قليل.',
    'تحديث توفر الإعلانات','تحتاج تأكيد التوفر','كل إعلاناتي',
    'لا توجد إعلانات في هذه القائمة حاليًا.','لا توجد محادثات بعد',
    'ما عندك رسائل غير مقروءة','غير المقروء فقط','محادثاتك','المحادثات غير المقروءة',
    'طلبات الدعم والبلاغات','طلبات الدعم','لا توجد حالات مطابقة.',
    'مفتوح','بانتظار المستخدم','مغلق - تم الحل','مغلق - مرفوض',
    'طلبات توثيق الحسابات','قيد المراجعة','يحتاج مستندًا إضافيًا','موثق','مرفوض',
    'الكل','مالك','دلال','مكتب عقارات','كل العملاء','تحتاج ردك','حان موعد المتابعة',
    'كل الحالات','جديد','تم التواصل','تمت المعاينة','غير مهتم','مكتمل',
    'الوارد','الأعمال','كل الأعمال','كل المهام','مغلقة','مكتملة','المنجزة',
    'مهامي','مسندة إليّ','غير مسندة','غير مسند','مسند لي','الإدارة','السوق'))

def numbers(value, fields):
    return isinstance(value,dict) and set(value)==fields and all(
        type(v) is int and 0<=v<=1_000_000 for v in value.values())

def safe_private_page_label(label):
    if label in CONTROLS or label in LABELS:
        return label
    if not isinstance(label,str) or not label.startswith('PC-META:') or len(label)>500:
        return None
    try: value=json.loads(label[8:])
    except (TypeError,ValueError): return None
    if not numbers(value,META) or value['v']!=1 or value['actor'] not in range(6):
        return None
    return 'PC-META:'+json.dumps(value,sort_keys=True,separators=(',',':'))

def private_page_events(log):
    rows=[]
    for line in log.splitlines():
        if 'AQER_PRIVATE:' not in line: continue
        try: value=json.loads(line.split('AQER_PRIVATE:',1)[1])
        except (TypeError,ValueError): continue
        # Historical1608 events did not record presence of total. Retain them
        # with explicit unknown metadata instead of inferring a missing total.
        if numbers(value,EVENT-{'totalKnown'}):
            value={**value,'totalKnown':0}
        if (not numbers(value,EVENT) or not 1<=value['surface']<=10 or
            value['actor'] not in range(1,6) or value['phase'] not in (1,2,3,4) or
            value['changed'] not in (0,1) or value['totalKnown'] not in (0,1) or value['page']<1): continue
        rows.append(value)
    return rows[-2000:]

def read_only_private_page_command(command):
    op,args=command.get('op'),command.get('args',{})
    if op not in {'observe','tap','scroll','back','login','logout','logout_in_place',
                  'wait','display','network','network_profile','private_metrics','batch','finish'}:
        return False
    if op=='batch':
        steps=args.get('steps')
        return isinstance(steps,list) and 1<=len(steps)<=6 and all(read_only_private_page_command(s) for s in steps)
    if op=='login' and args.get('alias') not in ('broker','regular','advertiser','manager','admin'):
        return False
    if op=='tap' and args.get('label') not in CONTROLS | LABELS:
        return False
    if op=='network_profile' and (set(args)!={'mode'} or args.get('mode') not in ('normal','slow')):
        return False
    return True
