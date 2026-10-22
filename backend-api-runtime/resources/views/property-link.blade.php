<!doctype html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>{{ $property->title }} | عقار</title>
    <meta name="description" content="{{ IlluminateSupportStr::limit(strip_tags((string) $property->description), 150) }}">
    <meta property="og:title" content="{{ $property->title }} | عقار">
    <meta property="og:description" content="{{ IlluminateSupportStr::limit(strip_tags((string) $property->description), 150) }}">
    <meta property="og:type" content="website">
    <meta property="og:url" content="{{ url('/l/properties/'.$property->id) }}">
    <style>
        body{font-family:system-ui,-apple-system,sans-serif;background:#f5f7fa;color:#192f48;margin:0}
        main{max-width:640px;margin:0 auto;padding:40px 20px}
        .card{background:#fff;border:1px solid #e3eaf1;border-radius:20px;padding:24px}
        .brand{color:#087c7c;font-weight:800;font-size:22px}.muted{color:#64748b}
        a.button{display:inline-block;background:#087c7c;color:#fff;text-decoration:none;padding:13px 20px;border-radius:12px;font-weight:700}
    </style>
</head>
<body>
<main>
    <div class="card">
        <div class="brand">عقار | Aqer عقارات اليمن</div>
        <h1>{{ $property->title }}</h1>
        <p class="muted">{{ $property->address }}</p>
        <p>{{ IlluminateSupportStr::limit(strip_tags((string) $property->description), 260) }}</p>
        <p><strong>{{ number_format((float) $property->price) }} {{ $property->currency }}</strong></p>
        <a class="button" href="realestate://app/properties/{{ $property->id }}">فتح في تطبيق عقار</a>
    </div>
</main>
</body>
</html>
