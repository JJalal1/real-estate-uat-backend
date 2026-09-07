<?php

namespace App\Services;

use App\Models\AccountVerificationProfile;
use App\Models\ListingReview;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertyPublicationBlock;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class ListingWorkflowService
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly PropertyAssetService $assets,
        private readonly RegionService $regions,
        private readonly BrokerListingVerificationService $brokerVerification,
        private readonly UserNotificationService $notifications,
    ) {}

    public function submit(User $actor, Property $listing, Request $request): Property
    {
        return DB::transaction(function () use ($actor, $listing, $request) {
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            if (! in_array($locked->review_status, ['draft', 'returned_for_correction'], true)) {
                throw new ConflictHttpException('This listing is not in a submittable state.');
            }
            if ($locked->images()->count() < 1) {
                throw new ConflictHttpException('At least one listing image is required before submission.');
            }

            $this->assertAdvertiserCanPublish($actor, $locked);
            $asset = PropertyAsset::query()->whereKey($locked->property_asset_id)->lockForUpdate()->firstOrFail();
            $this->assets->assertPurposeNotBlocked($asset, $locked->purpose);
            $this->assets->assertNotAlreadyPublished($asset, $locked->purpose, $locked->id);
            $this->regions->assertListingAllowed($actor, (float) $locked->latitude, (float) $locked->longitude);

            $from = $locked->review_status;
            $locked->forceFill([
                'status' => 'pending',
                'review_status' => 'submitted',
                'submitted_at' => now(),
                'reviewed_at' => null,
                'last_review_reason' => null,
                'review_assigned_to_user_id' => null,
                'review_assigned_at' => null,
            ])->save();

            $this->review($actor, $locked, 'submitted', $from, 'submitted');

            $candidates = $this->assets->likelyDuplicates($locked);
            if ($candidates !== []) {
                $this->review(
                    $actor,
                    $locked,
                    'duplicate_suspected',
                    'submitted',
                    'submitted',
                    'Likely duplicate signals require human review before approval.',
                    ['candidates' => $candidates],
                );
            }

            $this->audit->record(
                $actor,
                'listing.submitted',
                $locked,
                [
                    'review_status' => 'submitted',
                    'likely_duplicate_count' => count($candidates),
                ],
                $request,
                $actor->id,
            );

            return $locked->fresh(['images', 'documents', 'propertyAsset']);
        });
    }

    public function startReview(User $actor, Property $listing, Request $request): Property
    {
        return DB::transaction(function () use ($actor, $listing, $request) {
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            if (! in_array($locked->review_status, ['submitted', 'under_review'], true)) {
                throw new ConflictHttpException('Listing is not awaiting review.');
            }

            $assignedTo = (int) ($locked->review_assigned_to_user_id ?? 0);
            $isSupportWorker = $this->isSupportWorker($actor);

            if ($assignedTo > 0 && $assignedTo !== (int) $actor->id) {
                if ($isSupportWorker) {
                    throw new ConflictHttpException('تم استلام هذا الإعلان بالفعل بواسطة موظف دعم آخر.');
                }
                if ($locked->review_status === 'under_review') {
                    return $locked->fresh();
                }
            }

            if ($locked->review_status === 'under_review' && $assignedTo === (int) $actor->id) {
                return $locked->fresh();
            }

            $from = $locked->review_status;
            $locked->forceFill([
                'status' => 'pending',
                'review_status' => 'under_review',
                'review_assigned_to_user_id' => $actor->id,
                'review_assigned_at' => now(),
            ])->save();

            $this->review(
                $actor,
                $locked,
                'review_started',
                $from,
                'under_review',
                null,
                ['assigned_to_user_id' => $actor->id],
            );
            $this->audit->record(
                $actor,
                'listing.review_started',
                $locked,
                ['assigned_to_user_id' => $actor->id],
                $request,
                $locked->user_id,
            );

            return $locked->fresh();
        });
    }

    public function returnForCorrection(User $actor, Property $listing, string $reason, Request $request): Property
    {
        return DB::transaction(function () use ($actor, $listing, $reason, $request) {
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            $this->assertReviewable($locked, $actor);
            $from = $locked->review_status;
            $locked->forceFill([
                'status' => 'draft',
                'review_status' => 'returned_for_correction',
                'reviewed_at' => now(),
                'last_review_reason' => $reason,
                'review_assigned_to_user_id' => null,
                'review_assigned_at' => null,
            ])->save();

            $this->review($actor, $locked, 'returned_for_correction', $from, 'returned_for_correction', $reason);
            $this->audit->record(
                $actor,
                'listing.returned_for_correction',
                $locked,
                ['reason' => $reason],
                $request,
                $locked->user_id,
            );
            $this->notifications->create(
                (int) $locked->user_id,
                'listing_returned_for_correction',
                'إعلانك يحتاج تصحيحاً',
                $reason,
                'property',
                (int) $locked->id,
                ['review_status' => 'returned_for_correction'],
            );

            return $locked->fresh();
        });
    }

    public function approve(
        User $actor,
        Property $listing,
        ?string $reason,
        Request $request,
        ?string $duplicateReviewReason = null,
    ): Property {
        return DB::transaction(function () use ($actor, $listing, $reason, $request, $duplicateReviewReason) {
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            $this->assertReviewable($locked, $actor);

            $owner = $locked->user()->firstOrFail();
            $this->assertAdvertiserCanPublish($owner, $locked);
            $this->brokerVerification->assertApprovalAllowed($locked);

            $asset = PropertyAsset::query()->whereKey($locked->property_asset_id)->lockForUpdate()->firstOrFail();
            $this->assets->assertPurposeNotBlocked($asset, $locked->purpose);
            $this->assets->assertNotAlreadyPublished($asset, $locked->purpose, $locked->id);
            $this->regions->assertListingAllowed($owner, (float) $locked->latitude, (float) $locked->longitude);

            $candidates = $this->assets->likelyDuplicates($locked);
            if ($candidates !== []) {
                $acknowledgement = trim((string) $duplicateReviewReason);
                if (mb_strlen($acknowledgement) < 10) {
                    throw ValidationException::withMessages([
                        'duplicate_review_reason' => [
                            'توجد عقارات مشابهة محتملة. راجع المرشحات وسجل سبب اعتبار الإعلان غير مكرر، أو اربطه بهوية العقار الصحيحة قبل الموافقة.',
                        ],
                    ]);
                }
                $this->review(
                    $actor,
                    $locked,
                    'duplicate_review_cleared',
                    $locked->review_status,
                    $locked->review_status,
                    $acknowledgement,
                    ['candidates' => $candidates],
                );
                $this->audit->record(
                    $actor,
                    'listing.duplicate_review_cleared',
                    $locked,
                    [
                        'reason' => $acknowledgement,
                        'candidate_listing_ids' => array_column($candidates, 'listing_id'),
                    ],
                    $request,
                    $locked->user_id,
                );
            }

            $from = $locked->review_status;
            $locked->forceFill([
                'status' => 'published',
                'review_status' => 'approved',
                'published_at' => now(),
                'reviewed_at' => now(),
                'last_review_reason' => $reason,
                'review_assigned_to_user_id' => null,
                'review_assigned_at' => null,
            ])->save();

            $this->review($actor, $locked, 'approved', $from, 'approved', $reason);
            $this->audit->record(
                $actor,
                'listing.approved',
                $locked,
                ['reason' => $reason, 'duplicate_candidates_reviewed' => count($candidates)],
                $request,
                $locked->user_id,
            );
            $this->notifications->create(
                (int) $locked->user_id,
                'listing_approved',
                'تم اعتماد إعلانك ونشره',
                $locked->title,
                'property',
                (int) $locked->id,
                ['review_status' => 'approved'],
            );

            return $locked->fresh();
        });
    }

    public function finalRejectAndBlock(User $actor, Property $listing, string $reason, Request $request): Property
    {
        return DB::transaction(function () use ($actor, $listing, $reason, $request) {
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            $this->assertReviewable($locked, $actor);
            $asset = PropertyAsset::query()->whereKey($locked->property_asset_id)->lockForUpdate()->firstOrFail();

            $existing = PropertyPublicationBlock::query()
                ->where('property_asset_id', $asset->id)
                ->where('purpose', $locked->purpose)
                ->where('is_active', true)
                ->lockForUpdate()
                ->first();
            $block = $existing ?: PropertyPublicationBlock::query()->create([
                'property_asset_id' => $asset->id,
                'purpose' => $locked->purpose,
                'is_active' => true,
                'reason' => $reason,
                'blocked_by_user_id' => $actor->id,
                'source_listing_id' => $locked->id,
                'blocked_at' => now(),
            ]);

            $affected = Property::query()
                ->where('property_asset_id', $asset->id)
                ->where('purpose', $locked->purpose)
                ->lockForUpdate()
                ->get();
            foreach ($affected as $item) {
                $from = $item->review_status;
                $item->forceFill([
                    'status' => 'rejected',
                    'review_status' => 'rejected_blocked',
                    'reviewed_at' => now(),
                    'published_at' => null,
                    'last_review_reason' => $reason,
                    'review_assigned_to_user_id' => null,
                    'review_assigned_at' => null,
                ])->save();
                $action = $item->id === $locked->id ? 'final_rejected_blocked' : 'property_block_enforced';
                $this->review(
                    $actor,
                    $item,
                    $action,
                    $from,
                    'rejected_blocked',
                    $reason,
                    ['publication_block_id' => $block->id],
                );
            }

            $this->audit->record(
                $actor,
                'property.publication_block_created',
                $block,
                [
                    'property_asset_id' => $asset->id,
                    'purpose' => $locked->purpose,
                    'reason' => $reason,
                ],
                $request,
                $locked->user_id,
            );
            $this->notifications->create(
                (int) $locked->user_id,
                'listing_rejected',
                'تم رفض الإعلان',
                $reason,
                'property',
                (int) $locked->id,
                ['review_status' => 'rejected_blocked'],
            );

            return $locked->fresh();
        });
    }

    public function liftBlock(User $actor, PropertyPublicationBlock $block, string $reason, Request $request): PropertyPublicationBlock
    {
        if (! $block->is_active) {
            throw new ConflictHttpException('Publication block is already inactive.');
        }

        return DB::transaction(function () use ($actor, $block, $reason, $request) {
            $locked = PropertyPublicationBlock::query()->whereKey($block->id)->lockForUpdate()->firstOrFail();
            if (! $locked->is_active) {
                throw new ConflictHttpException('Publication block is already inactive.');
            }
            $locked->forceFill([
                'is_active' => false,
                'lifted_by_user_id' => $actor->id,
                'lifted_reason' => $reason,
                'lifted_at' => now(),
            ])->save();
            $this->audit->record(
                $actor,
                'property.publication_block_lifted',
                $locked,
                [
                    'property_asset_id' => $locked->property_asset_id,
                    'purpose' => $locked->purpose,
                    'reason' => $reason,
                ],
                $request,
            );
            return $locked->fresh();
        });
    }

    public function linkAsset(User $actor, Property $listing, PropertyAsset $asset, string $reason, Request $request): Property
    {
        return DB::transaction(function () use ($actor, $listing, $asset, $reason, $request) {
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            if ($this->isSupportWorker($actor)) {
                $this->assertReviewable($locked, $actor);
            }

            $targetAsset = PropertyAsset::query()->whereKey($asset->id)->lockForUpdate()->firstOrFail();
            $old = $locked->property_asset_id;
            $locked->forceFill(['property_asset_id' => $targetAsset->id])->save();
            $this->review(
                $actor,
                $locked,
                'property_identity_linked',
                $locked->review_status,
                $locked->review_status,
                $reason,
                [
                    'old_property_asset_id' => $old,
                    'new_property_asset_id' => $targetAsset->id,
                ],
            );
            $this->audit->record(
                $actor,
                'listing.property_identity_linked',
                $locked,
                [
                    'old_property_asset_id' => $old,
                    'new_property_asset_id' => $targetAsset->id,
                    'reason' => $reason,
                ],
                $request,
                $locked->user_id,
            );

            if ($this->assets->activeBlock($targetAsset, $locked->purpose)) {
                $locked->forceFill([
                    'status' => 'rejected',
                    'review_status' => 'rejected_blocked',
                    'reviewed_at' => now(),
                    'published_at' => null,
                    'last_review_reason' => 'Linked to an actively blocked physical property.',
                    'review_assigned_to_user_id' => null,
                    'review_assigned_at' => null,
                ])->save();
                $this->review(
                    $actor,
                    $locked,
                    'linked_to_blocked_property',
                    'under_review',
                    'rejected_blocked',
                    'Linked to an actively blocked physical property.',
                );
            }

            return $locked->fresh();
        });
    }

    private function assertAdvertiserCanPublish(User $advertiser, Property $property): void
    {
        $profile = $advertiser->verificationProfile();
        if ($profile) {
            if (! $profile->isApproved()) {
                throw new ConflictHttpException('يجب اعتماد نوع الحساب من فريق التحقق قبل إرسال إعلان للمراجعة.');
            }

            if (in_array($profile->type, [
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ], true)) {
                return;
            }

            if ($profile->type === AccountVerificationProfile::TYPE_OWNER) {
                if (! $property->documents()->where('kind', 'ownership_proof')->exists()) {
                    throw ValidationException::withMessages([
                        'ownership_proof' => ['يجب إرفاق مستند يثبت الملكية أو العلاقة بهذا العقار قبل الإرسال للمراجعة.'],
                    ]);
                }
                if (! $property->ownership_document_type
                    || ! $property->document_owner_name
                    || ! $property->owner_relationship_type) {
                    throw ValidationException::withMessages([
                        'ownership_relationship' => ['حدد نوع مستند الملكية واسم صاحب الحق وصفة علاقتك بالعقار.'],
                    ]);
                }
                if ($property->owner_relationship_type === 'owner'
                    && $this->normalizedName($property->document_owner_name) !== $this->normalizedName($advertiser->name)) {
                    throw ValidationException::withMessages([
                        'owner_relationship_type' => ['الاسم المدخل من مستند العقار لا يطابق اسم الحساب. اختر صفتك الصحيحة مثل وكيل أو وارث أو شريك.'],
                    ]);
                }
                if ($property->owner_relationship_type === 'other'
                    && trim((string) $property->owner_relationship_note) === '') {
                    throw ValidationException::withMessages([
                        'owner_relationship_note' => ['وضح صفتك أو علاقتك بالعقار.'],
                    ]);
                }
                return;
            }
        }

        // Compatibility with historical test/local identities that predate the
        // unified owner/broker/office verification policy. Current UAT accounts
        // use identity policy >= 1 and therefore must select a profile.
        if ((int) $advertiser->identity_policy_version === 0) {
            if (! $property->documents()->where('kind', 'ownership_or_authorization')->exists()) {
                throw ValidationException::withMessages([
                    'proof_documents' => ['أرفق إثبات ملكية أو تفويض قبل إرسال الإعلان للمراجعة.'],
                ]);
            }
            return;
        }

        if ($advertiser->isBrokerVerified()) {
            return;
        }

        throw new ConflictHttpException('اختر نوع الحساب من حسابي وأكمل التحقق قبل إرسال إعلان للمراجعة.');
    }

    private function normalizedName(?string $value): string
    {
        $text = mb_strtolower(trim((string) $value));
        $text = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $text) ?? $text;
        $text = strtr($text, ['أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ى' => 'ي', 'ؤ' => 'و', 'ئ' => 'ي', 'ة' => 'ه']);
        return preg_replace('/\s+/u', ' ', $text) ?? $text;
    }

    private function assertReviewable(Property $listing, ?User $actor = null): void
    {
        if (! in_array($listing->review_status, ['submitted', 'under_review'], true)) {
            throw new ConflictHttpException('Listing is not reviewable in its current state.');
        }
        if ($actor !== null && $this->isSupportWorker($actor)) {
            $assignedTo = (int) ($listing->review_assigned_to_user_id ?? 0);
            if ($assignedTo === 0) {
                throw new ConflictHttpException('استلم طلب تحقيق الإعلان أولاً قبل تنفيذ قرار المراجعة.');
            }
            if ($assignedTo !== (int) $actor->id) {
                throw new ConflictHttpException('تم استلام هذا الإعلان بواسطة موظف دعم آخر.');
            }
        }
    }

    private function isSupportWorker(User $actor): bool
    {
        return $actor->hasRole('support_agent') && ! $actor->hasPermission('support.manage');
    }

    private function review(
        ?User $actor,
        Property $listing,
        string $action,
        ?string $from,
        ?string $to,
        ?string $reason = null,
        array $metadata = [],
    ): ListingReview {
        return ListingReview::query()->create([
            'listing_id' => $listing->id,
            'actor_user_id' => $actor?->id,
            'actor_name_snapshot' => $actor?->name,
            'action' => $action,
            'from_review_status' => $from,
            'to_review_status' => $to,
            'reason' => $reason,
            'listing_snapshot' => $this->snapshot($listing),
            'metadata' => $metadata,
            'created_at' => now(),
        ]);
    }

    private function snapshot(Property $listing): array
    {
        return [
            'id' => $listing->id,
            'user_id' => $listing->user_id,
            'property_asset_id' => $listing->property_asset_id,
            'title' => $listing->title,
            'purpose' => $listing->purpose,
            'type' => $listing->type,
            'tenure_type' => $listing->tenure_type,
            'price' => (float) $listing->price,
            'latitude' => (float) $listing->latitude,
            'longitude' => (float) $listing->longitude,
            'status' => $listing->status,
            'review_status' => $listing->review_status,
        ];
    }
}
