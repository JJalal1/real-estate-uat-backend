<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\SavedSearchAlertService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ActiveWavePublicationAlertTest extends TestCase
{
    use RefreshDatabase;

    public function test_real_publication_event_notifies_after_commit_and_retries_do_not_duplicate(): void
    {
        $owner = $this->user('publisher'); $searcher = $this->user('subscriber');
        $token = 'publication_alert_fixture';
        $searcher->apiTokens()->create(['name' => 'test', 'token_hash' => hash('sha256',$token), 'token_prefix' => substr($token,0,12), 'expires_at' => now()->addHour()]);
        $this->withHeaders(['Authorization' => 'Bearer '.$token])->postJson('/api/saved-searches',
            ['name' => 'شقق ضمن الميزانية', 'filters' => ['purpose' => 'rent', 'type' => 'apartment', 'currency' => 'USD', 'max_monthly_rent' => 600]])->assertCreated();
        $property = Property::query()->create(['user_id' => $owner->id, 'title' => 'شقة جديدة فعلًا', 'type' => 'apartment', 'purpose' => 'rent',
            'price' => 6000, 'monthly_rent' => 500, 'currency' => 'USD', 'latitude' => 15.3, 'longitude' => 44.2, 'status' => 'draft', 'review_status' => 'draft']);
        DB::transaction(function () use ($property): void {
            $property->update(['status' => 'published', 'review_status' => 'approved', 'published_at' => now()]);
            $this->assertDatabaseCount('user_notifications', 0);
        });
        $this->assertDatabaseHas('user_notifications', ['user_id' => $searcher->id, 'type' => 'saved_search_match', 'entity_type' => 'property', 'entity_id' => $property->id]);
        $this->assertSame(0, app(SavedSearchAlertService::class)->notifyPublishedProperty($property->id));
        $this->assertSame(1, UserNotification::query()->where('type','saved_search_match')->count());
        $this->assertDatabaseCount('viewing_bookings', 0);
    }

    private function user(string $name): User
    {
        return User::query()->create(['name' => $name, 'email' => $name.'@publication.test', 'phone' => $name === 'publisher' ? '+967770111001' : '+967770111002',
            'phone_verified_at' => now(), 'profile_completed_at' => now(), 'account_status' => 'active', 'password' => Hash::make('fixture-password')]);
    }
}
