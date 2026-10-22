<?php

use App\Models\Property;
use App\Http\Controllers\AccountDeletionWebController;
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

Route::get('/account-deletion', [AccountDeletionWebController::class, 'show'])->name('account-deletion.show');
Route::post('/account-deletion/start', [AccountDeletionWebController::class, 'start'])
    ->middleware('throttle:5,60')
    ->name('account-deletion.start');
Route::post('/account-deletion/confirm', [AccountDeletionWebController::class, 'confirm'])
    ->middleware('throttle:5,60')
    ->name('account-deletion.confirm');
