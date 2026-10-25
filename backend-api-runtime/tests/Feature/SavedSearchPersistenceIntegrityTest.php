<?php

namespace Tests\Feature;

use App\Models\SavedPropertySearch;
use App\Models\User;
use Closure;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tests\TestCase;

class SavedSearchPersistenceIntegrityTest extends TestCase
{
    use RefreshDatabase;

    public function test_filter_collision_is_a_validation_error_and_preserves_both_saved_searches(): void
    {
        [$user, $headers] = $this->actor(1);
        $first = $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'Original land', 'filters' => ['type' => 'land'], 'alert_frequency' => 'off',
        ])->assertCreated()->json('data.id');
        $second = $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'Original villa', 'filters' => ['type' => 'villa'],
        ])->assertCreated()->json('data.id');
        $before = SavedPropertySearch::where('user_id', $user->id)->orderBy('id')->get()->toArray();

        $this->withHeaders($headers)->patchJson('/api/saved-searches/'.$second, [
            'name' => 'Must not partially persist', 'filters' => ['type' => 'land'], 'alert_frequency' => 'off',
        ])->assertUnprocessable()->assertJsonValidationErrors('filters');

        $this->assertSame($before, SavedPropertySearch::where('user_id', $user->id)->orderBy('id')->get()->toArray());
        $this->withHeaders($headers)->getJson('/api/saved-searches')->assertOk()->assertJsonCount(2, 'data');
        $this->assertNotSame($first, $second);
    }

    public function test_a_canonical_empty_search_cannot_subscribe_to_every_property(): void
    {
        [, $headers] = $this->actor(2);
        $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'Whitespace is not a search criterion', 'filters' => ['search' => '   '],
        ])->assertUnprocessable()->assertJsonValidationErrors('filters');
        $this->assertDatabaseCount('saved_property_searches', 0);
    }

    public function test_actor_deactivation_after_middleware_prevents_a_new_persistent_search(): void
    {
        [$user, $headers] = $this->actor(3);
        $route = app('router')->getRoutes()->match(Request::create('/api/saved-searches', 'POST'));
        $route->middleware(DeactivateSavedSearchActor::class);
        $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'Must not survive account deactivation', 'filters' => ['type' => 'land'],
        ])->assertForbidden();
        $this->assertDatabaseCount('saved_property_searches', 0);
        $this->assertSame(User::STATUS_SUSPENDED, $user->fresh()->account_status);
    }

    public function test_duplicate_create_preserves_the_existing_explicit_alert_configuration(): void
    {
        [$user, $headers] = $this->actor(4);
        $first = $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'Existing private name', 'filters' => ['type' => 'land'], 'alert_frequency' => 'off',
        ])->assertCreated()->json('data.id');
        $this->withHeaders($headers)->postJson('/api/saved-searches', [
            'name' => 'Different requested name', 'filters' => ['type' => 'land'], 'alert_frequency' => 'instant',
        ])->assertOk()->assertJsonPath('data.id', $first)
            ->assertJsonPath('data.name', 'Existing private name')->assertJsonPath('data.alert_frequency', 'off');
        $this->assertSame(1, SavedPropertySearch::where('user_id', $user->id)->count());
    }

    public function test_identical_filters_are_account_scoped_and_foreign_edits_remain_rejected(): void
    {
        [, $firstHeaders] = $this->actor(5);
        [, $secondHeaders] = $this->actor(6);
        $one = $this->withHeaders($firstHeaders)->postJson('/api/saved-searches', [
            'name' => 'First account', 'filters' => ['type' => 'land'],
        ])->assertCreated()->json('data.id');
        $two = $this->withHeaders($secondHeaders)->postJson('/api/saved-searches', [
            'name' => 'Second account', 'filters' => ['type' => 'land'],
        ])->assertCreated()->json('data.id');
        $this->assertNotSame($one, $two);
        $this->withHeaders($secondHeaders)->patchJson('/api/saved-searches/'.$one, ['name' => 'Foreign edit'])->assertNotFound();
        $this->withHeaders($secondHeaders)->deleteJson('/api/saved-searches/'.$one)->assertNotFound();
        $this->assertDatabaseHas('saved_property_searches', ['id' => $one, 'name' => 'First account']);
        $this->assertDatabaseCount('saved_property_searches', 2);
    }

    private function actor(int $number): array
    {
        $user = User::create(['name' => 'Synthetic search account '.$number,
            'email' => 'search-integrity-'.$number.'@example.invalid',
            'phone' => '+120255502'.str_pad((string) $number, 2, '0', STR_PAD_LEFT),
            'phone_verified_at' => now(), 'account_status' => User::STATUS_ACTIVE,
            'password' => 'synthetic-test-password']);
        $plain = 'synthetic-search-integrity-'.hash('sha256', (string) $number);
        $user->apiTokens()->create(['name' => 'disposable-only', 'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12), 'expires_at' => now()->addHour()]);
        return [$user, ['Authorization' => 'Bearer '.$plain, 'Accept' => 'application/json']];
    }
}

/** Reproduce an account changing after the HTTP active-account gate passed. */
class DeactivateSavedSearchActor
{
    public function handle(Request $request, Closure $next): Response
    {
        $request->user()->forceFill(['account_status' => User::STATUS_SUSPENDED])->save();
        return $next($request);
    }
}
