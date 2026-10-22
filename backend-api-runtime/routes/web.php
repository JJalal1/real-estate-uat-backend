<?php

use App\Models\Property;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/l/properties/{property}', function (Property $property) {
    abort_unless(
        $property->status === 'published' &&
        $property->availability_status === 'available',
        404,
    );

    return response()
        ->view('property-link', ['property' => $property])
        ->header('Cache-Control', 'public, max-age=60, stale-while-revalidate=120');
})->whereNumber('property');

Route::get('/.well-known/assetlinks.json', function () {
    $fingerprints=(array) config('app_links.android.sha256_cert_fingerprints',[]);
    if ($fingerprints===[]) return response()->json([],200,['Cache-Control'=>'public, max-age=300']);
    return response()->json([[
        'relation'=>['delegate_permission/common.handle_all_urls'],
        'target'=>[
            'namespace'=>'android_app',
            'package_name'=>(string) config('app_links.android.package_name'),
            'sha256_cert_fingerprints'=>array_values($fingerprints),
        ],
    ]],200,[
        'Cache-Control'=>'public, max-age=3600',
        'Content-Type'=>'application/json',
    ]);
});
