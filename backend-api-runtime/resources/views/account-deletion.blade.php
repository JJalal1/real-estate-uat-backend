<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>حذف حساب عقار | Aqer</title>
  <style>
    body{font-family:system-ui,-apple-system,sans-serif;background:#f4f7f8;color:#172b3a;margin:0}
    main{max-width:680px;margin:0 auto;padding:32px 18px 60px}
    .card{background:white;border:1px solid #dce6e9;border-radius:20px;padding:24px;margin-bottom:16px}
    h1{margin-top:0}.brand{color:#0d8a87;font-weight:800}.note{color:#52636f;line-height:1.8}
    label{display:block;font-weight:700;margin:14px 0 6px}input{width:100%;box-sizing:border-box;padding:13px;border:1px solid #b7c6cc;border-radius:10px;font:inherit}
    button{margin-top:16px;background:#0d8a87;color:white;border:0;border-radius:10px;padding:13px 18px;font:inherit;font-weight:700;cursor:pointer}
    .danger{background:#9f2d2d}.status{padding:12px;border-radius:10px;background:#eaf7f6}.error{color:#9f2d2d}
  </style>
</head>
<body>
<main>
  <div class="card">
    <div class="brand">عقار | Aqer عقارات اليمن</div>
    <h1>حذف الحساب والبيانات</h1>
    <p class="note">يمكنك حذف حساب عقار من داخل التطبيق أو من هذه الصفحة إذا لم يعد التطبيق مثبتًا لديك.</p>
    <p class="note">عند الحذف نلغي الوصول ونمسح بيانات الهوية ووثائق التحقق ونؤرشف الإعلانات. قد نحتفظ بالسجلات المالية والعقود وسجل التدقيق والرسائل المشتركة بالقدر اللازم لحماية حقوق الأطراف والالتزامات النظامية، تحت هوية محذوفة.</p>
  </div>

  @if($completed)
    <div class="card"><div class="status">تم حذف الحساب ومسح بيانات الهوية الشخصية المرتبطة به.</div></div>
  @else
    @if(session('status'))<div class="card"><div class="status">{{ session('status') }}</div></div>@endif
    @if($errors->any())<div class="card error">{{ $errors->first() }}</div>@endif

    <div class="card">
      <form method="post" action="{{ route('account-deletion.start') }}">
        @csrf
        <label for="login">البريد المؤكد أو رقم واتساب المسجل</label>
        <input id="login" name="login" autocomplete="username" required maxlength="190" value="{{ old('login') }}">
        <button type="submit">إرسال رمز التحقق</button>
      </form>
    </div>

    @if($otpStarted)
    <div class="card">
      <form method="post" action="{{ route('account-deletion.confirm') }}">
        @csrf
        <label for="code">رمز التحقق</label>
        <input id="code" name="code" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" required>
        <label for="confirm_phrase">للتأكيد اكتب: حذف حسابي نهائيًا</label>
        <input id="confirm_phrase" name="confirm_phrase" required>
        <button class="danger" type="submit">حذف الحساب نهائيًا</button>
      </form>
    </div>
    @endif
  @endif
</main>
</body>
</html>
