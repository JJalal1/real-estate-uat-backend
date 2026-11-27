<?php

namespace App\Services;

use App\Models\ListingReview;
use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertyPublicationBlock;
use App\Models\SupportTask;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

use function Illuminate\Support\defer;

class ListingWorkflowService
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly PropertyAssetService $assets,
        private readonly PropertyIdentityService $identity,
        private readonly RegionService $regions,
        private readonly BrokerListingVerificationService $brokerVerification,
        private readonly UserNotificationService $notifications,
        private readonly SupportTaskService $tasks,
        private readonly ListingDuplicateAssessment $duplicates,
    ) {}

    /** Human fallback only: no external provider, guessed rejection or automatic image deletion. */
    public function reviewMedia(User $actor, Property $listing, int $imageId, string $imageToken, string $decision, string $reason, Request $request): array
    {
        abort_unless($actor->hasPermission('listings.moderate'),403);
        return DB::transaction(function()use($actor,$listing,$imageId,$imageToken,$decision,$reason,$request):array {
            $locked=Property::query()->lockForUpdate()->findOrFail($listing->id);
            $this->assertReviewable($locked,$actor);
            $image=$locked->images()->whereKey($imageId)->lockForUpdate()->firstOrFail();
            $fingerprint=$this->mediaFingerprint($image);
            if (!hash_equals($fingerprint,$imageToken)) throw new ConflictHttpException('تغير ملف الصورة. حدّث الإعلان وراجع الصورة الجديدة.');
            $previous=$this->mediaReviewStates($locked)[$imageId] ?? null;
            if ($previous && $previous['decision']===$decision && $previous['reason']===$reason) return $previous;
            $review=$this->review($actor,$locked,'media_relevance_review',$locked->review_status,$locked->review_status,$reason,[
                'image_id'=>$imageId,'image_fingerprint'=>$fingerprint,'decision'=>$decision,'checker'=>'human_review',
            ]);
            $this->audit->record($actor,'listing.media_relevance_reviewed',$locked,[
                'image_id'=>$imageId,'decision'=>$decision,'review_id'=>$review->id,'checker'=>'human_review',
            ],$request,$locked->user_id);
            return ['decision'=>$decision,'reason'=>$reason,'checker'=>'human_review','review_id'=>$review->id];
        });
    }

    public function mediaReviewStates(Property $listing): array
    {
        $listing->loadMissing(['images','reviews']);
        $fingerprints=$listing->images->mapWithKeys(fn($image)=>[$image->id=>$this->mediaFingerprint($image)]);
        $states=[];
        foreach($listing->reviews->where('action','media_relevance_review')->sortByDesc('id') as $review) {
            $meta=$review->metadata ?? []; $id=(int)($meta['image_id'] ?? 0);
            if(isset($states[$id]) || !isset($fingerprints[$id]) || !hash_equals($fingerprints[$id],(string)($meta['image_fingerprint'] ?? ''))) continue;
            $states[$id]=['decision'=>$meta['decision'],'reason'=>$review->reason,'checker'=>'human_review','review_id'=>$review->id];
        }
        return $states;
    }

    public function mediaFingerprint(\App\Models\PropertyImage $image): string
    {
        return hash('sha256',(string)$image->path.'|'.(string)$image->cdn_url);
    }

    public function submit(User $actor, Property $listing, Request $request): Property
    {
        $request->validate(['publish_now' => ['sometimes', 'boolean'], 'upgrade_to_broker' => ['sometimes', 'boolean']]);
        $direct = $request->boolean('publish_now');
        $accepted = DB::transaction(function () use ($actor, $listing, $request, $direct) {
            $actor = User::query()->lockForUpdate()->findOrFail($actor->id);
            $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
            abort_unless((int) $actor->id === (int) $locked->user_id && $actor->canCreateListings(), 403);
            // A repeated submit after an interrupted mobile response returns the committed listing.
            if ($direct && ($locked->status === 'published' || in_array($locked->review_status, ['submitted', 'under_review'], true))) {
                return $locked;
            }
            if ($locked->status === 'archived' || ! in_array($locked->review_status, ['draft', 'returned_for_correction'], true)) {
                throw new ConflictHttpException('This listing is not in a submittable state.');
            }
            if ($locked->images()->count() < 1) {
                throw new ConflictHttpException('At least one listing image is required before submission.');
            }

            $from = $locked->review_status;
            if ($direct) {
                app(PropertySaiService::class)->assertReadyForSubmission($locked, $actor);
            }
            app(ListingAccessService::class)->authorizePublication($actor, $locked, $request);
            $asset = PropertyAsset::query()->whereKey($locked->property_asset_id)->lockForUpdate()->firstOrFail();
            $this->assets->assertPurposeNotBlocked($asset, $locked->purpose);
            $this->regions->assertListingAllowed($actor, (float) $locked->latitude, (float) $locked->longitude);

            if ($direct && $from === 'draft' && $this->publishIfDistinct($actor, $locked, $asset, $request)) {
                return $locked;
            }

            $locked->forceFill([
                'first_listed_at' => $locked->first_listed_at ?? now(),
                'status' => 'pending',
                'review_status' => 'submitted',
                'submitted_at' => now(),
                'reviewed_at' => null,
                'last_review_reason' => null,
                'review_assigned_to_user_id' => null,
                'review_assigned_at' => null,
                'duplicate_check_status' => 'pending',
                'duplicate_check_score' => 0,
                'duplicate_check_metadata' => null,
                'duplicate_checked_at' => null,
            ])->save();

            $this->review($actor, $locked, 'submitted', $from, 'submitted', metadata: ['marketplace_publish' => $direct]);
            $this->audit->record(
                $actor,
                'listing.submitted',
                $locked,
                [
                    'review_status' => 'submitted',
                    'property_identity_status' => 'pending',
                ],
                $request,
                $actor->id,
            );

            return $locked->fresh(['images', 'documents', 'propertyAsset']);
        });

        // The accepted request is committed before identity processing starts.
        // A failed or interrupted check remains retryable without a new submit.
        if (in_array($accepted->review_status, ['submitted', 'under_review'], true)) {
            $this->processSubmittedIdentity($actor, $accepted);
        }
        return $accepted->fresh(['images', 'documents', 'propertyAsset']);
    }

    private function publishIfDistinct(User $actor, Property $listing, PropertyAsset $asset, Request $request): bool
    {
        // Existing media findings and duplicate candidates keep their moderation workflow.
        foreach ($this->mediaReviewStates($listing) as $review) {
            if ($review['decision'] !== 'relevant') return false;
        }
        try {
            $distinct = DB::transaction(function () use ($listing, $actor): bool {
                $identity = $this->identity->evaluate($listing, $actor, true);
                return $identity['decision'] === 'distinct' && $this->assets->likelyDuplicates($listing) === [];
            });
        } catch (\Throwable $error) {
            Log::warning('Direct listing identity check needs review.', ['listing_id' => $listing->id, 'error_type' => $error::class]);
            return false;
        }
        if (! $distinct) return false;

        $this->assets->assertNotAlreadyPublished($asset, $listing->purpose, $listing->id);
        $this->identity->ensureRepresentation($listing);
        $listing->forceFill([
            'status' => 'published',
            'review_status' => 'approved',
            'first_listed_at' => $listing->first_listed_at ?? now(),
            'submitted_at' => now(),
            'published_at' => now(),
            'reviewed_at' => null,
            'last_review_reason' => null,
            'review_assigned_to_user_id' => null,
            'review_assigned_at' => null,
        ])->save();
        $this->review($actor, $listing, 'published_by_advertiser', 'draft', 'approved');
        $this->audit->record($actor, 'listing.published_by_advertiser', $listing,
            ['property_identity_status' => 'distinct'], $request, $actor->id);
        return true;
    }

    public function processSubmittedIdentity(User $actor, Property $listing): array
    {
        try {
            $result = DB::transaction(function () use ($actor, $listing): array {
                $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->firstOrFail();
                if (! in_array($locked->review_status, ['submitted', 'under_review'], true)) {
                    throw new ConflictHttpException('This listing is not awaiting identity review.');
                }
                if ($locked->duplicate_checked_at !== null
                    && in_array($locked->duplicate_check_status, ['distinct', 'needs_support', 'confirmed_duplicate'], true)) {
                    $metadata = $locked->duplicate_check_metadata ?? [];
                    return [
                        'decision' => match ($locked->duplicate_check_status) {
                            'confirmed_duplicate' => 'confirmed_duplicate',
                            'needs_support' => 'possible_duplicate',
                            default => 'distinct',
                        },
                        'status' => $locked->duplicate_check_status,
                        'score' => $locked->duplicate_check_score,
                        'signals' => $metadata['signals'] ?? [],
                        'candidate' => $metadata['candidate'] ?? null,
                        'message' => $metadata['message'] ?? null,
                    ];
                }

                $result = $this->identity->evaluate($locked, $actor, true);
                $signalContext = $this->identitySignalContext($locked, 'duplicate_suspected_after_submission');
                if (in_array($result['decision'] ?? 'distinct', ['possible_duplicate', 'confirmed_duplicate'], true)
                    && $signalContext !== null) {
                    $this->review(
                        $actor, $locked, 'duplicate_suspected_after_submission',
                        $locked->review_status, $locked->review_status,
                        'Automated identity evidence requires support review before publication.',
                        $signalContext + ['identity_result' => $result],
                    );
                }
                return $result;
            });
            $submission = $this->duplicates->submissionId($listing);
            defer(function () use ($result, $listing, $submission): void {
                $this->projectDuplicateEvidence((int) $listing->id);
                if ($submission === null || ! in_array($result['decision'], ['distinct', 'possible_duplicate'], true)) return;
                $job = new \App\Jobs\AssessListingPhotos((int) $listing->id, $submission);
                if (! app(BackgroundQueue::class)->submit('duplicates', $job)) {
                    $this->assessSubmittedPhotos($listing, $submission);
                }
            }, 'listing-duplicate-' . $listing->id);

            return $result;
        } catch (\Throwable $error) {
            Log::warning('Submitted listing identity check did not complete.', [
                'listing_id' => $listing->id, 'error_type' => $error::class,
            ]);
            try {
                DB::transaction(function () use ($actor, $listing): void {
                    $locked = Property::query()->whereKey($listing->id)->lockForUpdate()->first();
                    if (! $locked || ! in_array($locked->review_status, ['submitted', 'under_review'], true)
                        || $locked->duplicate_checked_at !== null) return;
                    $locked->forceFill(['duplicate_check_status' => 'check_failed'])->save();
                    $signalContext = $this->identitySignalContext($locked, 'identity_check_unavailable');
                    if ($signalContext !== null) {
                        $this->review($actor, $locked, 'identity_check_unavailable',
                            $locked->review_status, $locked->review_status,
                            'Identity evidence is unavailable; retry the check before approval.',
                            $signalContext);
                    }
                });
            } catch (\Throwable $markError) {
                // The committed pending state remains retryable if even the
                // failure marker cannot be stored during a database outage.
                Log::warning('Submitted identity failure marker could not be stored.', [
                    'listing_id' => $listing->id, 'error_type' => $markError::class,
                ]);
            }
            return [
                'decision' => 'unavailable', 'status' => 'check_failed',
                'score' => 0, 'signals' => [], 'candidate' => null,
            ];
        }
    }

    public function assessSubmittedPhotos(Property $listing, int $submission): void
    {
        $this->duplicates->assess($listing, $submission);
        $this->projectDuplicateEvidence((int) $listing->id);
    }

    private function projectDuplicateEvidence(int $listingId): void
    {
        DB::transaction(function () use ($listingId): void {
            $listing = Property::query()->lockForUpdate()->find($listingId);
            if (! $listing || ! in_array($listing->review_status, ['submitted', 'under_review'], true)) {
                return;
            }
            $evidence = $this->duplicates->evidence($listing, $this->assets->likelyDuplicates($listing));
            unset($evidence['likely_duplicate_candidates']);
            $this->tasks->projectListing($listing, $evidence);
        }, 3);
    }

    /** Keep one signal per submitted review, while retaining earlier cycles as evidence. */
    private function identitySignalContext(Property $listing, string $action): ?array
    {
        $submissionReviewId = (int) ListingReview::query()
            ->where('listing_id', $listing->id)->where('action', 'submitted')
            ->latest('id')->value('id');
        if (ListingReview::query()->where('listing_id', $listing->id)
            ->where('action', $action)->where('id', '>', $submissionReviewId)->exists()) {
            return null;
        }

        $previous = ListingReview::query()->where('listing_id', $listing->id)
            ->whereIn('action', ['duplicate_suspected_after_submission', 'identity_check_unavailable'])
            ->where('id', '<', $submissionReviewId)->latest('id')->first();
        $previousMetadata = $previous?->metadata ?? [];
        return [
            'submission_review_id' => $submissionReviewId ?: null,
            'previous_identity_signal_review_id' => $previous?->id,
            'previous_identity_decision' => $previous?->action === 'identity_check_unavailable'
                ? 'unavailable' : ($previousMetadata['identity_result']['decision'] ?? null),
        ];
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

            if ($locked->duplicate_checked_at === null
                || ! in_array($locked->duplicate_check_status, ['distinct', 'needs_support', 'confirmed_duplicate'], true)) {
                throw new ConflictHttpException('Identity evidence is incomplete. Retry the identity check before approval.');
            }

            // Publication is the human approval for the listing as a whole.
            // A review tied to a rejected current file still requires correction.
            $mediaStates = $this->mediaReviewStates($locked);
            $images = $locked->images()->get();
            if ($images->isEmpty()) {
                throw new ConflictHttpException('لا يمكن اعتماد إعلان بلا صور.');
            }
            $unrelatedImageIds = $images->filter(static fn ($image): bool =>
                ($mediaStates[$image->id]['decision'] ?? 'pending') === 'unrelated'
            );
            if ($unrelatedImageIds->isNotEmpty()) {
                throw new ConflictHttpException('لا يمكن اعتماد الإعلان قبل استبدال أو معالجة الصور المصنفة غير مرتبطة بالعقار.');
            }
            $owner = $locked->user()->firstOrFail();
            abort_unless($owner->canCreateListings(), 403);
            $this->brokerVerification->assertApprovalAllowed($locked);

            $asset = PropertyAsset::query()->whereKey($locked->property_asset_id)->lockForUpdate()->firstOrFail();
            $this->assets->assertPurposeNotBlocked($asset, $locked->purpose);
            $this->assets->assertNotAlreadyPublished($asset, $locked->purpose, $locked->id);
            $this->regions->assertListingAllowed($owner, (float) $locked->latitude, (float) $locked->longitude);

            $evidence = $this->duplicates->evidence($locked, $this->assets->likelyDuplicates($locked));
            $identityResult = $this->identity->assertApprovalAllowed($actor, $locked, $duplicateReviewReason);
            if ($identityResult['decision'] === 'possible_duplicate' || $evidence['duplicate_detection_source'] !== null) {
                $acknowledgement = trim((string) $duplicateReviewReason);
                if (mb_strlen($acknowledgement) < 10) {
                    throw ValidationException::withMessages([
                        'duplicate_review_reason' => ['اذكر سبب اعتبار الإعلان مختلفاً من عشرة أحرف على الأقل.'],
                    ]);
                }
                $resolution = [
                    'identity_result' => $identityResult,
                    'duplicate_detection_source' => $evidence['duplicate_detection_source'],
                    'duplicate_detection_signals' => $evidence['duplicate_detection_signals'],
                ];
                $this->review(
                    $actor,
                    $locked,
                    'duplicate_review_cleared',
                    $locked->review_status,
                    $locked->review_status,
                    $acknowledgement,
                    $resolution,
                );
                $this->audit->record(
                    $actor,
                    'listing.duplicate_review_cleared',
                    $locked,
                    ['reason' => $acknowledgement] + $resolution,
                    $request,
                    $locked->user_id,
                );
            }

            $this->identity->ensureRepresentation($locked);
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
                ['reason' => $reason, 'property_identity_status' => $identityResult['status'] ?? 'distinct'],
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

    public function rejectDuplicate(User $actor, Property $listing, int $candidateId, string $reason, Request $request): Property
    {
        abort_unless($actor->hasPermission('listings.moderate'), 403);
        $reason = trim($reason);
        if (mb_strlen($reason) < 10) {
            throw ValidationException::withMessages(['reason' => ['أضف سبباً واضحاً من عشرة أحرف على الأقل.']]);
        }

        return DB::transaction(function () use ($actor, $listing, $candidateId, $reason, $request): Property {
            $locked = Property::query()->lockForUpdate()->findOrFail($listing->id);
            $this->assertReviewable($locked, $actor);
            if ($locked->status !== 'pending') {
                throw new ConflictHttpException('الإعلان الجديد لا ينتظر قرار النشر.');
            }

            $previous = Property::query()->publiclyAvailable()
                ->whereKeyNot($locked->id)->whereKey($candidateId)->lockForUpdate()->first();
            $evidence = $this->duplicates->evidence($locked, $this->assets->likelyDuplicates($locked));
            if (! $previous || ! in_array($candidateId, array_column($evidence['likely_duplicate_candidates'], 'listing_id'), true)) {
                throw new ConflictHttpException('الإعلان السابق لم يعد متاحاً ضمن المقارنة. حدّث بيانات المراجعة.');
            }

            $sameOwner = (int) $previous->user_id === (int) $locked->user_id;
            $message = $sameOwner ? 'سبق نشره من قبلك. ' . $reason : $reason;
            $details = [
                'previous_property_id' => (int) $previous->id,
                'previous_listing_same_owner' => $sameOwner,
            ];
            $from = $locked->review_status;
            $locked->forceFill([
                'status' => 'rejected',
                'review_status' => 'rejected_duplicate',
                'reviewed_at' => now(),
                'published_at' => null,
                'last_review_reason' => $message,
                'review_assigned_to_user_id' => null,
                'review_assigned_at' => null,
            ])->save();
            $this->review($actor, $locked, 'rejected_duplicate', $from, 'rejected_duplicate', $reason, $details);
            $this->audit->record($actor, 'listing.rejected_duplicate', $locked, ['reason' => $reason] + $details, $request, $locked->user_id);
            $this->notifications->create(
                (int) $locked->user_id,
                'listing_duplicate_rejected',
                'تم رفض الإعلان المكرر',
                $message,
                'property',
                (int) $locked->id,
                ['review_status' => 'rejected_duplicate'] + $details,
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
            $task = SupportTask::query()->where('source_type', 'listing_review')
                ->where('source_id', $listing->id)->first();
            if ($task) {
                $visibleTask = $this->tasks->taskFor($actor, (int) $task->id, !empty($task->metadata['manager_agent_mode']));
                if ($visibleTask->isAwaitingAssignedReception()) {
                    throw new ConflictHttpException('استلم طلب تحقيق الإعلان أولاً قبل تنفيذ قرار المراجعة.');
                }
            }
        }
    }

    private function isSupportWorker(User $actor): bool
    {
        if ($actor->is_platform_owner || $actor->hasRole('super_admin')) return false;
        return $actor->hasRole('support_agent') || $actor->hasRole('support_manager');
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
        $review = ListingReview::query()->create([
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
        $this->tasks->projectListing($listing);
        return $review;
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
            'duplicate_check_status' => $listing->duplicate_check_status,
            'building_reference' => $listing->building_reference,
            'unit_number' => $listing->unit_number,
            'floor_number' => $listing->floor_number,
        ];
    }
}
