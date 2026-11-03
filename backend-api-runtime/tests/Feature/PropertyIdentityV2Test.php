<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\ListingReview;
use App\Models\Role;
use App\Models\User;
use App\Services\PropertyIdentityService;
use App\Services\PropertyAssetService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;
use Tests\TestCase;

class PropertyIdentityV2Test extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
    }

    public function test_confirmed_identity_signal_does_not_reject_review_submission(): void
    {
        [, $first] = $this->user('post-submit-house-1@example.test', '+967733001101');
        [, $second] = $this->user('post-submit-house-2@example.test', '+967733001102');

        $a = $this->createReady($first, [
            'title' => 'First synthetic house', 'type' => 'villa',
            'address' => 'صنعاء حي التجربة بيت 18',
            'latitude' => 15.369400, 'longitude' => 44.191000,
            'area_m2' => 420, 'bedrooms' => 6, 'bathrooms' => 4,
        ]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $b = $this->createReady($second, [
            'title' => 'Second synthetic house', 'type' => 'villa',
            'address' => 'صنعاء حي التجربة بيت 18',
            'latitude' => 15.369500, 'longitude' => 44.191060,
            'area_m2' => 421, 'bedrooms' => 6, 'bathrooms' => 4,
        ]);
        // The advertiser makes no separate identity-check request or assertion.
        $this->assertDatabaseMissing('property_identity_checks', ['property_id' => $b]);
        $this->withHeaders($second)->postJson("/api/properties/$b/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');

        $this->assertDatabaseHas('properties', [
            'id' => $b, 'status' => 'pending', 'review_status' => 'submitted',
        ]);
        $this->assertDatabaseHas('property_identity_checks', ['property_id' => $b]);
        $this->assertNotSame('distinct', Property::query()->findOrFail($b)->duplicate_check_status);
        $this->assertDatabaseHas('listing_reviews', ['listing_id' => $b, 'action' => 'duplicate_suspected_after_submission']);
    }

    public function test_possible_identity_signal_needs_no_self_verification_before_review_submission(): void
    {
        [, $first] = $this->user('post-submit-possible-1@example.test', '+967733001103');
        [, $second] = $this->user('post-submit-possible-2@example.test', '+967733001104');
        $common = [
            'type' => 'villa', 'address' => 'صنعاء حي التجربة شارع الأربعين',
            'area_m2' => 250, 'bedrooms' => 4, 'bathrooms' => 3,
        ];

        $a = $this->createReady($first, array_merge($common, [
            'title' => 'First synthetic villa',
            'latitude' => 15.340000, 'longitude' => 44.200000,
        ]));
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();
        $b = $this->createReady($second, array_merge($common, [
            'title' => 'Second synthetic villa',
            'latitude' => 15.340300, 'longitude' => 44.200120,
        ]));

        $this->withHeaders($second)->postJson("/api/properties/$b/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $listing = Property::query()->findOrFail($b);
        $this->assertNull($listing->duplicate_self_verification);
        $this->assertSame('needs_support', $listing->duplicate_check_status);
        $this->assertSame('possible_duplicate',
            app(PropertyIdentityService::class)->evaluate($listing, null, false)['decision']);
        $this->assertDatabaseHas('property_identity_checks', ['property_id' => $b]);
        $this->assertDatabaseHas('support_tasks', ['source_type' => 'listing_review', 'source_id' => $b]);
    }

    public function test_identity_processor_failure_keeps_submission_and_retries_without_duplicate_work(): void
    {
        [, $headers] = $this->user('identity-rollback@example.test', '+967733001107');
        [, $supportHeaders] = $this->user('identity-retry-support@example.test', '+967733001112', ['support_agent']);
        $id = $this->createReady($headers, ['title' => 'Rollback synthetic property']);

        $identity = new class extends PropertyIdentityService {
            public bool $fail = true;

            public function evaluate(Property $listing, ?User $actor = null, bool $persist = true): array
            {
                if ($this->fail) throw new \RuntimeException('Synthetic identity processor failure');
                return parent::evaluate($listing, $actor, $persist);
            }
        };
        $this->app->instance(PropertyIdentityService::class, $identity);

        $this->withHeaders($headers)->postJson("/api/properties/$id/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertDatabaseHas('properties', [
            'id' => $id, 'status' => 'pending', 'review_status' => 'submitted',
            'duplicate_check_status' => 'check_failed',
        ]);
        $this->assertDatabaseHas('listing_reviews', [
            'listing_id' => $id, 'action' => 'submitted',
        ]);
        $this->assertDatabaseHas('support_tasks', ['source_type' => 'listing_review', 'source_id' => $id]);
        $this->assertDatabaseMissing('property_identity_checks', ['property_id' => $id]);
        $this->withHeaders($supportHeaders)->postJson("/api/admin/listing-review/listings/$id/approve")
            ->assertStatus(409);
        $this->assertDatabaseHas('properties', ['id' => $id, 'status' => 'pending', 'review_status' => 'submitted']);
        $this->withHeaders($headers)->postJson("/api/properties/$id/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'check_failed');
        $this->assertSame(1, \DB::table('listing_reviews')->where('listing_id', $id)
            ->where('action', 'identity_check_unavailable')->count());
        $identity->fail = false;
        try {
            $identity->assertApprovalAllowed(User::query()->findOrFail(Property::query()->findOrFail($id)->user_id), Property::query()->findOrFail($id));
            $this->fail('Approval cannot bypass an incomplete identity check.');
        } catch (ConflictHttpException $exception) {
            $this->assertSame(409, $exception->getStatusCode());
        }
        $firstCheck = $this->withHeaders($headers)->postJson("/api/properties/$id/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'distinct');
        $cachedCheck = $this->withHeaders($headers)->postJson("/api/properties/$id/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'distinct');
        $this->assertSame($firstCheck->json('data.message'), $cachedCheck->json('data.message'));
        $this->assertDatabaseCount('property_identity_checks', 1);
        $this->assertDatabaseHas('properties', ['id' => $id, 'review_status' => 'submitted', 'duplicate_check_status' => 'distinct']);
        $this->assertSame(1, \DB::table('listing_reviews')->where('listing_id', $id)->where('action', 'submitted')->count());
        $this->assertSame(1, \DB::table('support_tasks')->where('source_type', 'listing_review')->where('source_id', $id)->count());
    }

    public function test_pending_identity_check_can_resume_without_resubmitting(): void
    {
        [, $headers] = $this->user('identity-pending@example.test', '+967733001111');
        $id = $this->createReady($headers, ['title' => 'Pending synthetic property']);

        $workflow = new class(
            app(\App\Services\AuditLogService::class),
            app(PropertyAssetService::class),
            app(PropertyIdentityService::class),
            app(\App\Services\RegionService::class),
            app(\App\Services\BrokerListingVerificationService::class),
            app(\App\Services\UserNotificationService::class),
            app(\App\Services\SupportTaskService::class),
        ) extends \App\Services\ListingWorkflowService {
            public bool $skipOnce = true;

            public function processSubmittedIdentity(User $actor, Property $listing): array
            {
                if ($this->skipOnce) {
                    $this->skipOnce = false;
                    return ['status' => 'pending'];
                }
                return parent::processSubmittedIdentity($actor, $listing);
            }
        };
        $this->app->instance(\App\Services\ListingWorkflowService::class, $workflow);
        $this->withHeaders($headers)->postJson("/api/properties/$id/submit")->assertOk();

        // Simulate a process exit at the accepted-commit boundary. The journal
        // is append-only, so no rows are removed or rewritten for this test.
        $this->assertDatabaseHas('properties', [
            'id' => $id, 'review_status' => 'submitted', 'duplicate_check_status' => 'pending',
        ]);
        $this->assertDatabaseMissing('property_identity_checks', ['property_id' => $id]);
        $this->withHeaders($headers)->postJson("/api/properties/$id/submit")->assertStatus(409);
        $this->withHeaders($headers)->postJson("/api/properties/$id/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'distinct');
        $this->assertSame(1, \DB::table('property_identity_checks')->where('property_id', $id)->count());
        $this->assertSame(1, \DB::table('listing_reviews')->where('listing_id', $id)
            ->where('action', 'submitted')->count());
    }

    public function test_suspected_identity_retry_creates_one_support_signal_and_keeps_other_users_out(): void
    {
        [, $firstHeaders] = $this->user('identity-retry-first@example.test', '+967733001108');
        [, $secondHeaders] = $this->user('identity-retry-second@example.test', '+967733001109');
        [, $otherHeaders] = $this->user('identity-retry-other@example.test', '+967733001110');
        $common = [
            'type' => 'villa', 'address' => 'Synthetic house number 18',
            'latitude' => 15.369400, 'longitude' => 44.191000,
            'area_m2' => 420, 'bedrooms' => 6, 'bathrooms' => 4,
        ];
        $identity = new class extends PropertyIdentityService {
            public bool $fail = false;

            public function evaluate(Property $listing, ?User $actor = null, bool $persist = true): array
            {
                if ($this->fail) throw new \RuntimeException('Synthetic identity processor failure');
                return parent::evaluate($listing, $actor, $persist);
            }
        };
        $this->app->instance(PropertyIdentityService::class, $identity);
        $firstId = $this->createReady($firstHeaders, array_merge($common, ['title' => 'First reviewable home']));
        $this->withHeaders($firstHeaders)->postJson("/api/properties/$firstId/submit")->assertOk();
        $secondId = $this->createReady($secondHeaders, array_merge($common, [
            'title' => 'Second reviewable home', 'latitude' => 15.369500, 'longitude' => 44.191060,
        ]));
        $identity->fail = true;
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'check_failed');
        $this->withHeaders($otherHeaders)->postJson("/api/properties/$secondId/identity/check")->assertForbidden();
        $identity->fail = false;
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'possible_duplicate');
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'possible_duplicate');
        $this->assertSame(1, \DB::table('property_identity_checks')->where('property_id', $secondId)->count());
        $this->assertSame(1, \DB::table('listing_reviews')->where('listing_id', $secondId)
            ->where('action', 'duplicate_suspected_after_submission')->count());
        $this->assertSame(1, \DB::table('support_tasks')->where('source_type', 'listing_review')
            ->where('source_id', $secondId)->count());
        $this->assertDatabaseHas('properties', [
            'id' => $secondId, 'status' => 'pending', 'review_status' => 'submitted',
            'duplicate_check_status' => 'needs_support',
        ]);
    }

    public function test_return_edit_resubmit_records_a_new_suspected_identity_signal_per_cycle(): void
    {
        [, $firstHeaders] = $this->user('identity-cycle-first@example.test', '+967733001113');
        [, $secondHeaders] = $this->user('identity-cycle-second@example.test', '+967733001114');
        [, $moderatorHeaders] = $this->user('identity-cycle-moderator@example.test', '+967733001115', ['content_moderator']);
        $firstId = $this->createReady($firstHeaders, ['title' => 'First physical property']);
        $this->withHeaders($firstHeaders)->postJson("/api/properties/$firstId/submit")->assertOk();
        $secondId = $this->createReady($secondHeaders, ['title' => 'Second physical property']);
        Property::query()->findOrFail($secondId)->forceFill([
            'property_asset_id' => Property::query()->findOrFail($firstId)->property_asset_id,
        ])->save();
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'confirmed_duplicate');
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');
        $this->assertSame(1, \DB::table('listing_reviews')->where('listing_id', $secondId)
            ->where('action', 'duplicate_suspected_after_submission')->count());

        $this->withHeaders($moderatorHeaders)->postJson("/api/admin/listing-review/listings/$secondId/return", [
            'reason' => 'Clarify the synthetic property details before another review.',
        ])->assertOk();
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId", [
            'title' => 'Second physical property, clarified',
        ])->assertOk();
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'confirmed_duplicate');
        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');
        $this->assertSame(2, \DB::table('listing_reviews')->where('listing_id', $secondId)
            ->where('action', 'submitted')->count());
        $this->assertSame(2, \DB::table('listing_reviews')->where('listing_id', $secondId)
            ->where('action', 'duplicate_suspected_after_submission')->count());
        $cycles = ListingReview::query()->where('listing_id', $secondId)
            ->where('action', 'submitted')->orderBy('id')->pluck('id')->all();
        $signals = ListingReview::query()->where('listing_id', $secondId)
            ->where('action', 'duplicate_suspected_after_submission')->orderBy('id')->get();
        $this->assertSame($cycles[0], $signals[0]->metadata['submission_review_id']);
        $this->assertSame($cycles[1], $signals[1]->metadata['submission_review_id']);
        $this->assertSame($signals[0]->id, $signals[1]->metadata['previous_identity_signal_review_id']);
        $this->assertSame('confirmed_duplicate', $signals[1]->metadata['previous_identity_decision']);
        $this->assertSame(1, \DB::table('support_tasks')->where('source_type', 'listing_review')
            ->where('source_id', $secondId)->count());
    }

    public function test_return_edit_resubmit_records_a_new_check_failure_signal_per_cycle(): void
    {
        [, $ownerHeaders] = $this->user('identity-failure-cycle@example.test', '+967733001116');
        [, $moderatorHeaders] = $this->user('identity-failure-moderator@example.test', '+967733001117', ['content_moderator']);
        $id = $this->createReady($ownerHeaders, ['title' => 'First synthetic attempt']);
        $this->app->instance(PropertyIdentityService::class, new class extends PropertyIdentityService {
            public function evaluate(Property $listing, ?User $actor = null, bool $persist = true): array
            {
                throw new \RuntimeException('Synthetic identity processor failure');
            }
        });
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'check_failed');
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'check_failed');
        $this->assertSame(1, \DB::table('listing_reviews')->where('listing_id', $id)
            ->where('action', 'identity_check_unavailable')->count());

        $this->withHeaders($moderatorHeaders)->postJson("/api/admin/listing-review/listings/$id/return", [
            'reason' => 'Retry after the synthetic identity service becomes available.',
        ])->assertOk();
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id", [
            'title' => 'Second synthetic attempt',
        ])->assertOk();
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/submit")
            ->assertOk()->assertJsonPath('data.duplicate_check_status', 'check_failed');
        $this->withHeaders($ownerHeaders)->postJson("/api/properties/$id/identity/check")
            ->assertOk()->assertJsonPath('data.status', 'check_failed');
        $this->assertSame(2, \DB::table('listing_reviews')->where('listing_id', $id)
            ->where('action', 'submitted')->count());
        $this->assertSame(2, \DB::table('listing_reviews')->where('listing_id', $id)
            ->where('action', 'identity_check_unavailable')->count());
        $cycles = ListingReview::query()->where('listing_id', $id)
            ->where('action', 'submitted')->orderBy('id')->pluck('id')->all();
        $signals = ListingReview::query()->where('listing_id', $id)
            ->where('action', 'identity_check_unavailable')->orderBy('id')->get();
        $this->assertSame($cycles[0], $signals[0]->metadata['submission_review_id']);
        $this->assertSame($cycles[1], $signals[1]->metadata['submission_review_id']);
        $this->assertSame($signals[0]->id, $signals[1]->metadata['previous_identity_signal_review_id']);
        $this->assertSame('unavailable', $signals[1]->metadata['previous_identity_decision']);
        $this->assertSame(1, \DB::table('support_tasks')->where('source_type', 'listing_review')
            ->where('source_id', $id)->count());
    }

    public function test_moving_pin_does_not_bypass_same_house_detection(): void
    {
        [, $first] = $this->user('identity-house-1@example.test', '+967733000001');
        [, $second] = $this->user('identity-house-2@example.test', '+967733000002');

        $a = $this->createReady($first, [
            'title' => 'فيلا حدة الأصلية', 'type' => 'villa', 'address' => 'صنعاء حدة شارع 14 بيت 18',
            'latitude' => 15.369400, 'longitude' => 44.191000, 'area_m2' => 420, 'bedrooms' => 6, 'bathrooms' => 4,
        ]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $b = $this->createReady($second, [
            'title' => 'فيلا للبيع', 'type' => 'villa', 'address' => 'صنعاء - حدة - شارع 14 - بيت 18',
            'latitude' => 15.369500, 'longitude' => 44.191060, 'area_m2' => 421, 'bedrooms' => 6, 'bathrooms' => 4,
        ]);

        $this->withHeaders($second)->postJson("/api/properties/$b/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');
        $this->withHeaders($second)->postJson("/api/properties/$b/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertDatabaseHas('properties', ['id' => $b, 'duplicate_check_status' => 'confirmed_duplicate']);
        $this->assertDatabaseHas('listing_reviews', ['listing_id' => $b, 'action' => 'duplicate_suspected_after_submission']);
    }

    public function test_adjacent_real_properties_are_allowed_when_identity_signals_differ(): void
    {
        [, $first] = $this->user('identity-neighbour-1@example.test', '+967733000003');
        [, $second] = $this->user('identity-neighbour-2@example.test', '+967733000004');
        $a = $this->createReady($first, [
            'title' => 'البيت الشمالي', 'address' => 'صنعاء بيت بوس شارع أ مبنى 10',
            'latitude' => 15.300000, 'longitude' => 44.210000, 'area_m2' => 180, 'area_value' => 180, 'bedrooms' => 3, 'bathrooms' => 2,
        ]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $b = $this->createReady($second, [
            'title' => 'البيت الجنوبي', 'address' => 'صنعاء بيت بوس شارع ب مبنى 11',
            'latitude' => 15.300700, 'longitude' => 44.210040, 'area_m2' => 340, 'area_value' => 340, 'bedrooms' => 5, 'bathrooms' => 4,
        ]);
        $this->withHeaders($second)->postJson("/api/properties/$b/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'distinct');
        $this->withHeaders($second)->postJson("/api/properties/$b/submit")->assertOk();
    }

    public function test_same_building_same_unit_is_blocked_but_different_unit_is_allowed(): void
    {
        [, $first] = $this->user('identity-unit-1@example.test', '+967733000005');
        [, $second] = $this->user('identity-unit-2@example.test', '+967733000006');
        [, $third] = $this->user('identity-unit-3@example.test', '+967733000007');

        $common = [
            'type' => 'apartment', 'address' => 'صنعاء حدة شارع صفر مبنى النور',
            'building_reference' => 'عمارة النور 12', 'floor_number' => '3',
            'latitude' => 15.370000, 'longitude' => 44.190000, 'area_m2' => 130, 'bedrooms' => 3, 'bathrooms' => 2,
        ];
        $a = $this->createReady($first, array_merge($common, ['title' => 'شقة 7', 'unit_number' => '7']));
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $same = $this->createReady($second, array_merge($common, [
            'title' => 'نفس الشقة بدبوس محرك', 'unit_number' => '7', 'latitude' => 15.370070, 'longitude' => 44.190050,
        ]));
        $this->withHeaders($second)->postJson("/api/properties/$same/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');
        $this->withHeaders($second)->postJson("/api/properties/$same/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');

        $different = $this->createReady($third, array_merge($common, ['title' => 'شقة 8', 'unit_number' => '8']));
        $this->withHeaders($third)->postJson("/api/properties/$different/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'distinct');
        $this->withHeaders($third)->postJson("/api/properties/$different/submit")->assertOk();
    }

    public function test_land_boundary_prevents_pin_shift_and_allows_adjacent_parcel(): void
    {
        [, $first] = $this->user('identity-land-1@example.test', '+967733000008');
        [, $second] = $this->user('identity-land-2@example.test', '+967733000009');
        [, $third] = $this->user('identity-land-3@example.test', '+967733000010');

        $polygon = $this->polygon([[44.1800,15.3600],[44.1810,15.3600],[44.1810,15.3610],[44.1800,15.3610]]);
        $a = $this->createReady($first, ['type'=>'land','title'=>'قطعة أ','address'=>'حدة مخطط 5 قطعة 21','latitude'=>15.3605,'longitude'=>44.1805,'area_m2'=>1200,'bedrooms'=>null,'bathrooms'=>null,'land_boundary_geojson'=>$polygon]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();

        $same = $this->createReady($second, ['type'=>'land','title'=>'نفس القطعة','address'=>'حدة مخطط 5 قطعة 21','latitude'=>15.3608,'longitude'=>44.1808,'area_m2'=>1200,'bedrooms'=>null,'bathrooms'=>null,'land_boundary_geojson'=>$polygon]);
        $this->withHeaders($second)->postJson("/api/properties/$same/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'confirmed_duplicate');

        $adjacentPolygon = $this->polygon([[44.1811,15.3600],[44.1821,15.3600],[44.1821,15.3610],[44.1811,15.3610]]);
        $adjacent = $this->createReady($third, ['type'=>'land','title'=>'قطعة مجاورة','address'=>'حدة مخطط 5 قطعة 22','latitude'=>15.3605,'longitude'=>44.1816,'area_m2'=>1190,'bedrooms'=>null,'bathrooms'=>null,'land_boundary_geojson'=>$adjacentPolygon]);
        $this->withHeaders($third)->postJson("/api/properties/$adjacent/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'distinct');
    }

    public function test_ambiguous_case_can_be_self_verified_and_routes_to_existing_review(): void
    {
        [, $first] = $this->user('identity-gray-1@example.test', '+967733000011');
        [, $second] = $this->user('identity-gray-2@example.test', '+967733000012');

        $a = $this->createReady($first, ['title'=>'منزل أول','address'=>'صنعاء حدة شارع الجامعة رقم 40','latitude'=>15.340000,'longitude'=>44.200000,'area_m2'=>250,'bedrooms'=>4,'bathrooms'=>3]);
        $this->withHeaders($first)->postJson("/api/properties/$a/submit")->assertOk();
        $b = $this->createReady($second, ['title'=>'منزل قريب','address'=>'صنعاء حدة جوار السوق الخلفي','latitude'=>15.340300,'longitude'=>44.200120,'area_m2'=>252,'bedrooms'=>4,'bathrooms'=>3]);

        $this->withHeaders($second)->postJson("/api/properties/$b/identity/check")
            ->assertOk()->assertJsonPath('data.decision', 'possible_duplicate')
            ->assertJsonPath('data.status', 'self_verification_required');
        $this->withHeaders($second)->postJson("/api/properties/$b/identity/self-verify", [
            'assert_different' => true,
            'difference_type' => 'different_address',
            'difference_note' => 'هذا منزل مستقل مجاور وله مدخل ورقم مبنى مختلف عن العقار الآخر.',
        ])->assertOk()->assertJsonPath('data.status', 'needs_support');

        $this->withHeaders($second)->postJson("/api/properties/$b/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertDatabaseHas('listing_reviews', ['listing_id'=>$b,'action'=>'duplicate_suspected_after_submission']);
        $this->assertDatabaseHas('support_tasks', ['source_type'=>'listing_review','source_id'=>$b]);
    }

    public function test_published_asset_can_enter_review_but_publication_guard_still_rejects_it(): void
    {
        [, $firstHeaders] = $this->user('identity-published-1@example.test', '+967733001105');
        [, $secondHeaders] = $this->user('identity-published-2@example.test', '+967733001106');
        $firstId = $this->createReady($firstHeaders, ['title' => 'Published synthetic property']);
        $first = Property::query()->findOrFail($firstId);
        $first->forceFill(['status' => 'published', 'review_status' => 'approved'])->saveQuietly();

        $secondId = $this->createReady($secondHeaders, ['title' => 'Reviewable synthetic property']);
        Property::query()->findOrFail($secondId)
            ->forceFill(['property_asset_id' => $first->property_asset_id])->saveQuietly();

        $this->withHeaders($secondHeaders)->postJson("/api/properties/$secondId/submit")
            ->assertOk()->assertJsonPath('data.review_status', 'submitted');
        $this->assertDatabaseHas('listing_reviews', [
            'listing_id' => $secondId, 'action' => 'duplicate_suspected_after_submission',
        ]);

        $this->expectException(ConflictHttpException::class);
        app(PropertyAssetService::class)->assertNotAlreadyPublished(
            $first->propertyAsset, $first->purpose, $secondId,
        );
    }

    public function test_representation_claim_conflict_is_controlled_and_preserves_the_winner(): void
    {
        [$firstUser, $firstHeaders] = $this->user('identity-claim-1@example.test', '+967733000014');
        [$secondUser, $secondHeaders] = $this->user('identity-claim-2@example.test', '+967733000015');

        $firstId = $this->createReady($firstHeaders, [
            'title' => 'العقار صاحب التمثيل',
            'address' => 'صنعاء حدة شارع 50 منزل 1',
            'latitude' => 15.371000,
            'longitude' => 44.192000,
        ]);
        $secondId = $this->createReady($secondHeaders, [
            'title' => 'عقار ثان لاختبار تعارض التمثيل',
            'address' => 'صنعاء شملان شارع 20 منزل 8',
            'latitude' => 15.430000,
            'longitude' => 44.150000,
        ]);

        $first = Property::query()->findOrFail($firstId);
        $second = Property::query()->findOrFail($secondId);
        $second->forceFill(['property_asset_id' => $first->property_asset_id])->saveQuietly();

        $identity = app(PropertyIdentityService::class);
        $identity->ensureRepresentation($first);
        $identity->ensureRepresentation($first); // idempotent for the same advertiser.

        try {
            $identity->ensureRepresentation($second);
            $this->fail('A competing advertiser must not acquire an active representation claim.');
        } catch (ConflictHttpException $exception) {
            $this->assertSame(409, $exception->getStatusCode());
        }

        $this->assertDatabaseCount('property_representation_claims', 1);
        $this->assertDatabaseHas('property_representation_claims', [
            'property_asset_id' => $first->property_asset_id,
            'property_id' => $first->id,
            'advertiser_user_id' => $firstUser->id,
            'status' => 'active',
        ]);
        $this->assertDatabaseMissing('property_representation_claims', [
            'advertiser_user_id' => $secondUser->id,
            'status' => 'active',
        ]);
    }

    public function test_identity_audit_journal_rejects_mutation(): void
    {
        [, $headers] = $this->user('identity-audit@example.test', '+967733000013');
        $id = $this->createReady($headers, ['title'=>'عقار تدقيق']);
        $this->withHeaders($headers)->postJson("/api/properties/$id/identity/check")->assertOk();
        $check = \DB::table('property_identity_checks')->where('property_id',$id)->first();
        $this->assertNotNull($check);
        $this->expectException(\Throwable::class);
        \DB::table('property_identity_checks')->where('id',$check->id)->update(['score'=>99]);
    }

    private function createReady(array $headers, array $overrides = []): int
    {
        $response = $this->withHeaders($headers)->post('/api/properties', $this->payload(array_merge([
            'images' => [UploadedFile::fake()->image('home.jpg')],
            'proof_documents' => [UploadedFile::fake()->image('proof.jpg')],
        ], $overrides)));
        $response->assertCreated();
        return (int) $response->json('data.id');
    }

    private function user(string $email, string $phone, array $roles = ['registered_user']): array
    {
        $user = User::query()->create([
            'name'=>'Property Identity User','email'=>$email,'phone'=>$phone,'phone_verified_at'=>now(),
            'account_status'=>User::STATUS_ACTIVE,'password'=>Hash::make(hash('sha256',$email.'|identity-v2')),
        ]);
        foreach ($roles as $key) {
            $role = Role::query()->where('key', $key)->firstOrFail();
            $user->roles()->attach($role->id, ['assigned_by_user_id' => null, 'created_at' => now()]);
        }
        $plain='identity_'.substr(hash('sha512',$email),0,76);
        $user->apiTokens()->create(['name'=>'identity-test','token_hash'=>hash('sha256',$plain),'token_prefix'=>substr($plain,0,12),'expires_at'=>now()->addHour()]);
        return [$user,['Authorization'=>'Bearer '.$plain,'Accept'=>'application/json']];
    }

    private function payload(array $overrides=[]): array
    {
        return array_merge([
            'listing_input_version'=>3,'title'=>'Property Identity V2','description'=>'Identity regression property.',
            'purpose'=>'sale','type'=>'house','tenure_type'=>'freehold','price'=>50000000,'currency'=>'YER',
            'area_m2'=>220,'area_value'=>220,'area_unit'=>'sqm','bedrooms'=>4,'bathrooms'=>3,'has_parking'=>true,'building_facade'=>'north',
            'address'=>'صنعاء حدة شارع رئيسي','latitude'=>15.3694,'longitude'=>44.1910,'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000',
        ],$overrides);
    }

    private function polygon(array $points): array
    {
        return ['type'=>'Polygon','coordinates'=>[array_merge($points,[$points[0]])]];
    }
}
