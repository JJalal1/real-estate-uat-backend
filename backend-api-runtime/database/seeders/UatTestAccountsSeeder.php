<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use RuntimeException;

class UatTestAccountsSeeder extends Seeder
{
    /** @var array<int,array<string,mixed>> */
    private const ACCOUNTS = [
        [
            'key' => 'regular_1',
            'name' => 'مستخدم عادي تجريبي 1',
            'email' => 'uat-regular-1@example.invalid',
            'phone' => '+12025550101',
            'account_type' => 'regular',
            'roles' => [],
        ],
        [
            'key' => 'regular_2',
            'name' => 'مستخدم عادي تجريبي 2',
            'email' => 'uat-regular-2@example.invalid',
            'phone' => '+12025550102',
            'account_type' => 'regular',
            'roles' => [],
        ],
        [
            'key' => 'broker_unverified',
            'name' => 'دلال تجريبي غير موثق',
            'email' => 'uat-broker-unverified@example.invalid',
            'phone' => '+12025550103',
            'account_type' => 'broker',
            'broker_status' => 'not_submitted',
            'roles' => [],
        ],
        [
            'key' => 'broker_verified_1',
            'name' => 'دلال تجريبي موثق 1',
            'email' => 'uat-broker-verified-1@example.invalid',
            'phone' => '+12025550104',
            'account_type' => 'broker',
            'broker_status' => 'approved',
            'roles' => ['broker'],
        ],
        [
            'key' => 'broker_verified_2',
            'name' => 'دلال تجريبي موثق 2',
            'email' => 'uat-broker-verified-2@example.invalid',
            'phone' => '+12025550105',
            'account_type' => 'broker',
            'broker_status' => 'approved',
            'roles' => ['broker'],
        ],
        [
            'key' => 'support_agent_1',
            'name' => 'موظف دعم تجريبي 1',
            'email' => 'uat-support-agent-1@example.invalid',
            'phone' => '+12025550106',
            'account_type' => 'regular',
            'roles' => ['support_agent'],
        ],
        [
            'key' => 'support_agent_2',
            'name' => 'موظف دعم تجريبي 2',
            'email' => 'uat-support-agent-2@example.invalid',
            'phone' => '+12025550107',
            'account_type' => 'regular',
            'roles' => ['support_agent'],
        ],
        [
            'key' => 'support_manager',
            'name' => 'مدير الدعم التجريبي',
            'email' => 'uat-support-manager@example.invalid',
            'phone' => '+12025550108',
            'account_type' => 'regular',
            'roles' => ['support_manager'],
        ],
        [
            'key' => 'general_manager',
            'name' => 'المدير العام التجريبي',
            'email' => 'uat-general-manager@example.invalid',
            'phone' => '+12025550109',
            'account_type' => 'regular',
            'roles' => ['super_admin'],
            'is_platform_owner' => true,
        ],
    ];

    public function run(): void
    {
        if (! app()->environment('uat', 'staging', 'testing')) {
            throw new RuntimeException('UAT test accounts may run only in uat/staging/testing.');
        }

        $requiredRoles = [
            'registered_user',
            'broker',
            'support_agent',
            'support_manager',
            'super_admin',
        ];
        $roleIds = DB::table('roles')->whereIn('key', $requiredRoles)->pluck('id', 'key');
        $missingRoles = array_values(array_filter(
            $requiredRoles,
            static fn (string $key): bool => ! isset($roleIds[$key]),
        ));
        if ($missingRoles !== []) {
            throw new RuntimeException('Required UAT roles are missing: '.implode(', ', $missingRoles));
        }

        $now = now();
        $ids = [];

        DB::transaction(function () use ($now, $roleIds, &$ids): void {
            // UAT keeps one deterministic primary owner account.
            DB::table('users')->where('is_platform_owner', true)->update([
                'is_platform_owner' => false,
                'updated_at' => $now,
            ]);

            foreach (self::ACCOUNTS as $account) {
                $existing = DB::table('users')
                    ->where('phone', $account['phone'])
                    ->orWhere('email', $account['email'])
                    ->first();

                $isBroker = $account['account_type'] === 'broker';
                $brokerStatus = $isBroker ? ($account['broker_status'] ?? 'not_submitted') : 'not_required';
                $verifiedBroker = $isBroker && $brokerStatus === 'approved';

                $common = [
                    'name' => $account['name'],
                    'email' => $account['email'],
                    'phone' => $account['phone'],
                    'email_verified_at' => $now,
                    'phone_verified_at' => $now,
                    'identity_policy_version' => 1,
                    'account_status' => 'active',
                    'is_platform_owner' => (bool) ($account['is_platform_owner'] ?? false),
                    'updated_at' => $now,
                ];

                // Keep the designated UAT role accounts deterministic. These are test-only users.
                if ($account['key'] !== 'regular_1' && $account['key'] !== 'regular_2') {
                    $common['account_type'] = $account['account_type'];
                    $common['broker_verification_status'] = $brokerStatus;
                    $common['broker_verification_submitted_at'] = $verifiedBroker ? $now->copy()->subDay() : null;
                    $common['broker_verified_at'] = $verifiedBroker ? $now : null;
                    $common['broker_verified_by_user_id'] = null;
                    $common['broker_verification_note'] = $verifiedBroker ? 'UAT seeded verified broker.' : null;
                }

                if ($existing) {
                    DB::table('users')->where('id', $existing->id)->update($common);
                    $userId = (int) $existing->id;
                } else {
                    $common += [
                        'password' => Hash::make(Str::random(96)),
                        'account_type' => $account['account_type'],
                        'broker_verification_status' => $brokerStatus,
                        'broker_verification_submitted_at' => $verifiedBroker ? $now->copy()->subDay() : null,
                        'broker_verified_at' => $verifiedBroker ? $now : null,
                        'broker_verified_by_user_id' => null,
                        'broker_verification_note' => $verifiedBroker ? 'UAT seeded verified broker.' : null,
                        'created_at' => $now,
                    ];
                    $userId = (int) DB::table('users')->insertGetId($common);
                }

                $ids[$account['key']] = $userId;

                // Do not delete manually granted roles/permissions. Only ensure the baseline role(s).
                $roleKeys = array_values(array_unique(array_merge(['registered_user'], $account['roles'])));
                foreach ($roleKeys as $roleKey) {
                    DB::table('user_role')->insertOrIgnore([
                        'user_id' => $userId,
                        'role_id' => $roleIds[$roleKey],
                        'assigned_by_user_id' => null,
                        'created_at' => $now,
                    ]);
                }
            }

            $ownerId = $ids['general_manager'];
            foreach (['broker_verified_1', 'broker_verified_2'] as $brokerKey) {
                DB::table('users')->where('id', $ids[$brokerKey])->update([
                    'broker_verified_by_user_id' => $ownerId,
                    'updated_at' => $now,
                ]);
            }
        });

        $allowed = config('services.whatsapp.uat_test_otp.phone_numbers', []);
        $allowed = is_array($allowed)
            ? array_map(static fn ($v): string => trim((string) $v), $allowed)
            : [];
        $missingPhones = array_values(array_filter(
            array_column(self::ACCOUNTS, 'phone'),
            static fn (string $phone): bool => ! in_array($phone, $allowed, true),
        ));

        if ($missingPhones !== [] && $this->command) {
            $this->command->warn('UAT_TEST_PHONE_NUMBERS is missing: '.implode(',', $missingPhones));
        }

        if ($this->command) {
            $this->command->info('UAT test accounts seeded: '.count(self::ACCOUNTS));
        }
    }
}
