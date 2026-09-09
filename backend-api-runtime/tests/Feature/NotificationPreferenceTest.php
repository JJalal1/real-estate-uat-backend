<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\UserNotificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class NotificationPreferenceTest extends TestCase
{
    use RefreshDatabase;

    public function test_preferences_default_on_and_are_account_bound(): void
    {
        [$user, $headers] = $this->user('prefs@example.test', '+967771100001');
        [$other, $otherHeaders] = $this->user('other-prefs@example.test', '+967771100002');

        $this->withHeaders($headers)->getJson('/api/notification-preferences')
            ->assertOk()
            ->assertJsonPath('data.messages', true)
            ->assertJsonPath('data.viewings', true)
            ->assertJsonPath('data.agreements', true)
            ->assertJsonPath('data.listing_activity', true)
            ->assertJsonPath('data.discovery_alerts', true)
            ->assertJsonPath('data.services', true)
            ->assertJsonPath('data.essential_always_on', true);

        $this->withHeaders($headers)->patchJson('/api/notification-preferences', [
            'messages' => false,
            'discovery_alerts' => false,
        ])->assertOk()
            ->assertJsonPath('data.messages', false)
            ->assertJsonPath('data.discovery_alerts', false)
            ->assertJsonPath('data.viewings', true);

        $this->withHeaders($otherHeaders)->getJson('/api/notification-preferences')
            ->assertOk()
            ->assertJsonPath('data.messages', true)
            ->assertJsonPath('data.discovery_alerts', true);

        $this->assertDatabaseHas('user_notification_preferences', [
            'user_id' => $user->id,
            'messages' => false,
            'discovery_alerts' => false,
        ]);
        $this->assertDatabaseHas('user_notification_preferences', [
            'user_id' => $other->id,
            'messages' => true,
            'discovery_alerts' => true,
        ]);
    }

    public function test_disabled_product_category_is_suppressed_but_essential_notice_remains(): void
    {
        [$user, $headers] = $this->user('delivery-prefs@example.test', '+967771100003');

        $this->withHeaders($headers)->patchJson('/api/notification-preferences', [
            'messages' => false,
            'viewings' => false,
            'agreements' => false,
            'listing_activity' => false,
            'discovery_alerts' => false,
            'services' => false,
        ])->assertOk();

        $notifications = app(UserNotificationService::class);
        $this->assertNull($notifications->create($user->id, 'message_received', 'رسالة جديدة'));
        $this->assertNull($notifications->create($user->id, 'booking_confirmed', 'موعد معاينة'));
        $this->assertNull($notifications->create($user->id, 'agreement_created', 'اتفاق جديد'));
        $this->assertNull($notifications->create($user->id, 'saved_search_match', 'عقار مطابق'));
        $this->assertNull($notifications->create($user->id, 'listing_review_returned', 'الإعلان يحتاج تعديل'));
        $this->assertNull($notifications->create($user->id, 'service_order_ready', 'الخدمة جاهزة'));

        $essential = $notifications->create(
            $user->id,
            'support_reply',
            'رد جديد من الدعم',
        );
        $this->assertNotNull($essential);

        $this->assertSame(
            1,
            DB::table('user_notifications')->where('user_id', $user->id)->count(),
        );
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $user->id,
            'type' => 'support_reply',
        ]);
    }

    public function test_reenabling_category_restores_delivery(): void
    {
        [$user, $headers] = $this->user('restore-prefs@example.test', '+967771100004');

        $this->withHeaders($headers)->patchJson('/api/notification-preferences', [
            'messages' => false,
        ])->assertOk();
        $this->assertNull(app(UserNotificationService::class)->create(
            $user->id,
            'message_received',
            'لن يصل',
        ));

        $this->withHeaders($headers)->patchJson('/api/notification-preferences', [
            'messages' => true,
        ])->assertOk();
        $created = app(UserNotificationService::class)->create(
            $user->id,
            'message_received',
            'وصلت رسالة',
        );
        $this->assertNotNull($created);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $user->id,
            'type' => 'message_received',
            'title' => 'وصلت رسالة',
        ]);
    }

    private function user(string $email, string $phone): array
    {
        $user = User::query()->create([
            'name' => 'Preference User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
        $plain = 'prefs_'.substr(hash('sha512', $email), 0, 80);
        $user->apiTokens()->create([
            'name' => 'notification-preference-test',
            'token_hash' => hash('sha256', $plain),
            'token_prefix' => substr($plain, 0, 12),
            'expires_at' => now()->addHour(),
        ]);

        return [$user, [
            'Authorization' => 'Bearer '.$plain,
            'Accept' => 'application/json',
        ]];
    }
}
