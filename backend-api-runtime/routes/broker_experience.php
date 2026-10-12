<?php

use App\Http\Controllers\Api\BrokerExperienceController;
use Illuminate\Support\Facades\Route;

Route::get('/brokers', [BrokerExperienceController::class,'directory']);
Route::get('/advertisers/{advertiser}/profile', [BrokerExperienceController::class,'publicProfile']);
Route::get('/advertisers/{advertiser}/photo', [BrokerExperienceController::class,'photo']);
Route::post('/properties/{property}/view', [BrokerExperienceController::class,'recordView'])->middleware('throttle:120,1');

Route::middleware(['auth.api','account.active'])->group(function (): void {
    Route::get('/broker/workspace', [BrokerExperienceController::class,'workspace']);
    Route::patch('/broker/profile', [BrokerExperienceController::class,'updateProfile']);
    Route::post('/broker/profile/photo', [BrokerExperienceController::class,'uploadPhoto']);
    Route::post('/broker/support/tasks/{task}/resolution', [BrokerExperienceController::class,'resolveDeal'])->middleware('permission:support.handle_reports');
    Route::get('/broker/customers', [BrokerExperienceController::class,'customers']);
    Route::patch('/broker/customers/{thread}/stage', [BrokerExperienceController::class,'updateCustomer']);
    Route::post('/broker/customers/{thread}/completed-deal', [BrokerExperienceController::class,'reportDeal']);
    Route::get('/broker/listings/availability', [BrokerExperienceController::class,'listingAvailability']);
    Route::post('/broker/listings/availability', [BrokerExperienceController::class,'changeAvailability']);
    Route::get('/broker/activity', [BrokerExperienceController::class,'activity']);
    Route::get('/broker/deals/{outcome}', [BrokerExperienceController::class,'deal']);
    Route::post('/broker/deals/{outcome}/decision', [BrokerExperienceController::class,'decideDeal']);
    Route::get('/broker/finance', [BrokerExperienceController::class,'finance']);
});
