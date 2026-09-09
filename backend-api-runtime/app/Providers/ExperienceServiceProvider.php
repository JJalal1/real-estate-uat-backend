<?php

namespace App\Providers;

use App\Http\Controllers\Api\ProfessionalWorkspaceController;
use App\Http\Controllers\Api\SavedPropertySearchController;
use App\Models\Property;
use App\Observers\PropertyExperienceObserver;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

class ExperienceServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        Property::observe(PropertyExperienceObserver::class);

        Route::prefix('api')
            ->middleware(['auth.api', 'account.active'])
            ->group(function (): void {
                Route::get('/saved-searches', [SavedPropertySearchController::class, 'index']);
                Route::post('/saved-searches', [SavedPropertySearchController::class, 'store']);
                Route::patch('/saved-searches/{savedSearch}', [SavedPropertySearchController::class, 'update']);
                Route::delete('/saved-searches/{savedSearch}', [SavedPropertySearchController::class, 'destroy']);
                Route::get('/professional/workspace', [ProfessionalWorkspaceController::class, 'show']);
            });
    }
}
