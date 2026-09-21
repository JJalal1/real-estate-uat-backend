<?php

namespace Tests\Feature;

use App\Models\PropertyPaymentMethod;
use App\Models\Role;
use App\Models\User;
use App\Services\PropertyFinancialService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class FinancialV1CompletionTest extends TestCase
{
    use RefreshDatabase;

    public function test_general_manager_finance_workspace_and_method_configuration_are_authoritative(): void
    {
        [$owner, $headers] = $this->adminUser();

        $this->withHeaders($headers)
            ->getJson('/api/admin/finance/workspace?period=30d&transaction_type=sale&advertiser_type=owner')
            ->assertOk()
            ->assertJsonStructure(['data'=>[
                'filters','summary','deals','payments','payouts','receivables','overdue','holds','refunds','disputes','audit_log',
            ]])
            ->assertJsonPath('data.filters.period', '30d')
            ->assertJsonPath('data.filters.transaction_type', 'sale')
            ->assertJsonPath('data.filters.advertiser_type', 'owner');

        $method = PropertyPaymentMethod::query()->where('key', 'jeeb')->firstOrFail();
        $this->withHeaders($headers)
            ->patchJson('/api/admin/finance/payment-methods/'.$method->id, [
                'is_enabled'=>true,
                'allows_full_payment'=>false,
                'allows_sai_only'=>true,
                'min_amount'=>100,
                'max_amount'=>500000,
            ])
            ->assertOk()
            ->assertJsonPath('data.allows_full_payment', false)
            ->assertJsonPath('data.allows_sai_only', true)
            ->assertJsonPath('data.min_amount', 100)
            ->assertJsonPath('data.max_amount', 500000);

        $this->assertDatabaseHas('audit_logs', [
            'actor_user_id'=>$owner->id,
            'action'=>'finance.payment_method_updated',
        ]);

        $methods = app(PropertyFinancialService::class)->paymentMethods(1000, 'YER', 'platform_full');
        $jeeb = collect($methods)->firstWhere('key', 'jeeb');
        $this->assertNotNull($jeeb);
        $this->assertFalse((bool) $jeeb['available']);
        $this->assertSame('هذه الوسيلة غير مفعلة للدفع الكامل للصفقة.', $jeeb['unavailable_reason']);

        $saiMethods = app(PropertyFinancialService::class)->paymentMethods(1000, 'YER', 'platform_sai_only');
        $jeebSai = collect($saiMethods)->firstWhere('key', 'jeeb');
        $this->assertTrue((bool) $jeebSai['available']);
    }

    public function test_non_finance_user_cannot_access_general_manager_financial_configuration(): void
    {
        [, $headers] = $this->regularUser();

        $this->withHeaders($headers)->getJson('/api/admin/finance/workspace')->assertForbidden();
        $this->withHeaders($headers)->getJson('/api/admin/finance/payment-methods')->assertForbidden();
    }

    private function adminUser(): array
    {
        return $this->user('financial-completion-admin@example.test', '+967772000091', ['super_admin']);
    }

    private function regularUser(): array
    {
        return $this->user('financial-completion-user@example.test', '+967772000092', []);
    }

    private function user(string $email, string $phone, array $roles): array
    {
        $user = User::query()->create([
            'name'=>'Financial V1 Completion User',
            'email'=>$email,
            'phone'=>$phone,
            'phone_verified_at'=>now(),
            'profile_completed_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,
            'password'=>Hash::make('financial-v1-completion-password'),
        ]);

        $roleIds=[];
        foreach(array_unique(array_merge(['registered_user'],$roles)) as $key){
            $role=Role::query()->where('key',$key)->firstOrFail();
            $roleIds[$role->id]=['assigned_by_user_id'=>null,'created_at'=>now()];
        }
        $user->roles()->sync($roleIds);
        $plain='finv1complete_'.substr(hash('sha512',$email),0,64);
        $user->apiTokens()->create([
            'name'=>'financial-v1-completion',
            'token_hash'=>hash('sha256',$plain),
            'token_prefix'=>substr($plain,0,12),
            'expires_at'=>now()->addHour(),
        ]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }
}
