<?php

namespace App\Providers;

use App\Http\Controllers\Api\FinancialPropertyController;
use App\Http\Controllers\Api\PropertyController;
use App\Http\Middleware\EnsureSupportTaskOwnership;
use App\Services\FinancialAwareSupportTaskService;
use App\Services\SupportTaskService;
use Illuminate\Routing\Events\RouteMatched;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->bind(SupportTaskService::class, FinancialAwareSupportTaskService::class);
        $this->app->bind(PropertyController::class, FinancialPropertyController::class);
    }

    public function boot(): void
    {
        if (! $this->app->routesAreCached()) {
            Route::middleware(['api', 'auth.api', 'account.active'])
                ->prefix('api/admin/workspace')
                ->group(base_path('routes/support_workspace.php'));
            Route::middleware(['api', 'auth.api', 'account.active'])
                ->prefix('api')
                ->group(base_path('routes/financial_v1.php'));
        }

        Event::listen(RouteMatched::class, function (RouteMatched $event): void {
            $uri = $event->route->uri();
            $sensitive =
                (str_starts_with($uri, 'api/admin/account-verifications/')
                    && preg_match('#/(approve|more-info|reject)$#', $uri) === 1)
                || str_starts_with($uri, 'api/account-verification/users/')
                || str_starts_with($uri, 'api/admin/support/cases/');
            if ($sensitive) $event->route->middleware(EnsureSupportTaskOwnership::class);
        });
    }
}
