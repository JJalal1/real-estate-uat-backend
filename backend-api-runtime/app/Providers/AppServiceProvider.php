<?php

namespace App\Providers;

use App\Http\Middleware\EnsureSupportTaskOwnership;
use Illuminate\Routing\Events\RouteMatched;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        // The workspace routes are kept separate so the existing API contract is not rewritten.
        if (! $this->app->routesAreCached()) {
            Route::middleware(['api', 'auth.api', 'account.active'])
                ->prefix('api/admin/workspace')
                ->group(base_path('routes/support_workspace.php'));
        }

        // Add ownership enforcement only to sensitive legacy actions, after the route is matched.
        // This preserves old API contracts while making the new claim/assignee state authoritative.
        Event::listen(RouteMatched::class, function (RouteMatched $event): void {
            $uri = $event->route->uri();
            $sensitive =
                (str_starts_with($uri, 'api/admin/account-verifications/')
                    && preg_match('#/(approve|more-info|reject)$#', $uri) === 1)
                || str_starts_with($uri, 'api/account-verification/users/')
                || str_starts_with($uri, 'api/admin/support/cases/');

            if ($sensitive) {
                $event->route->middleware(EnsureSupportTaskOwnership::class);
            }
        });
    }
}
