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
