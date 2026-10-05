<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\ServiceOffering;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class Stage14ServicesPaymentsApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_paid_service_and_payment_routes_are_dormant_in_free_core(): void
    {
        [, $customerHeaders] = $this->user('w4b-services@example.test', '+967760100001');
        [, $adminHeaders] = $this->user('w4b-services-admin@example.test', '+967760100002', ['super_admin']);

        $offer = ServiceOffering::query()->where('code', 'account_pro_30d')->firstOrFail();
        $this->assertFalse((bool) $offer->is_active);

        $before = [
            'orders' => DB::table('service_orders')->count(),
            'entitlements' => DB::table('service_entitlements')->count(),
            'events' => DB::table('payment_events')->count(),
        ];

        $this->getJson('/api/services/catalog')->assertNotFound();
        $this->withHeaders($customerHeaders)
            ->postJson('/api/services/orders', ['offering_id' => $offer->id])
            ->assertNotFound();
        $this->withHeaders($customerHeaders)
            ->getJson('/api/services/orders/mine')
            ->assertNotFound();
        $this->withHeaders($adminHeaders)
            ->getJson('/api/admin/payments/orders')
            ->assertNotFound();
        $this->withHeaders($adminHeaders)
            ->postJson('/api/admin/payments/orders/999/settle', [
                'provider' => 'manual_admin',
                'provider_reference' => 'DISABLED',
            ])
            ->assertNotFound();

        $after = [
            'orders' => DB::table('service_orders')->count(),
            'entitlements' => DB::table('service_entitlements')->count(),
            'events' => DB::table('payment_events')->count(),
        ];
        $this->assertSame($before, $after);
    }

    public function test_historical_paid_service_schema_permissions_and_templates_are_preserved_inactive(): void
    {
        foreach ([
            'service_offerings',
            'service_orders',
            'service_entitlements',
            'payment_events',
            'viewing_bookings',
            'viewing_booking_events',
        ] as $table) {
            $this->assertTrue(Schema::hasTable($table));
        }

        $this->assertDatabaseHas('permissions', ['key' => 'services.manage']);
        $this->assertDatabaseHas('permissions', ['key' => 'payments.manage']);

        $support = Role::query()->where('key', 'support_manager')->firstOrFail();
        $super = Role::query()->where('key', 'super_admin')->firstOrFail();
        $services = DB::table('permissions')->where('key', 'services.manage')->value('id');
        $payments = DB::table('permissions')->where('key', 'payments.manage')->value('id');

        $this->assertTrue(DB::table('role_permission')->where('role_id', $support->id)->where('permission_id', $services)->exists());
        $this->assertFalse(DB::table('role_permission')->where('role_id', $support->id)->where('permission_id', $payments)->exists());
        $this->assertTrue(DB::table('role_permission')->where('role_id', $super->id)->where('permission_id', $payments)->exists());

        $templates = ServiceOffering::query()
            ->whereIn('code', ['listing_featured_7d', 'listing_featured_30d', 'account_pro_30d']);
        $this->assertSame(3, $templates->count());
        $this->assertSame(0, (clone $templates)->where('is_active', true)->count());

        $columns = array_merge(
            Schema::getColumnListing('service_orders'),
            Schema::getColumnListing('payment_events'),
        );
        foreach ($columns as $column) {
            $this->assertDoesNotMatchRegularExpression('/card|pan|cvv|cvc|password|secret|token/i', $column);
        }

        $this->assertDatabaseHas('permissions', ['key' => 'bookings.manage']);
        $this->assertDatabaseHas('permissions', ['key' => 'conversations.review_private']);
    }

    private function user(string $email, string $phone, array $roles = []): array
    {
        $user = User::query()->create([
            'name' => 'W4b Service User',
            'email' => $email,
            'phone' => $phone,
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);

        $sync = [];
        foreach (array_unique(array_merge(['registered_user'], $roles)) as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $sync[$role->id] = [
                'assigned_by_user_id' => null,
                'created_at' => now(),
            ];
        }
        $user->roles()->sync($sync);

        $plain = 'w4bsvc_'.substr(hash('sha512', $email), 0, 72);
        $user->apiTokens()->create([
            'name' => 'w4b-service',
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
