<?php

namespace App\Services;

use App\Models\ListingReview;
use App\Models\Property;
use App\Models\PropertyImage;
use Illuminate\Support\Facades\DB;
use RuntimeException;

class ListingDuplicateAssessment
{
    private const PENDING = ['submitted', 'under_review'];
    private const STARTED = 'duplicate_ai_assessment_started';
    private const FINISHED = 'duplicate_ai_assessed';
    private const PHOTO_READ_TIMEOUT_SECONDS = 4;
    private const PHOTO_SIGNALS = [
        'matching_interior' => 'تقارب الموقع والمواصفات وظهرت تفاصيل داخلية متطابقة في الصور.',
        'matching_property_features' => 'تقارب الموقع والمواصفات وظهرت سمات مميزة للعقار نفسه في الصور.',
    ];

    public function __construct(
        private readonly PropertyAssetService $assets,
        private readonly ListingImageService $images,
        private readonly CloudAssetStorageService $storage,
        private readonly GeminiClient $gemini,
    ) {}

    public function assess(Property $listing, ?int $expectedSubmission = null): void
    {
        if (! $this->gemini->available()) return;

        $listing = $listing->fresh(['images', 'propertyAsset']);
        if (! $listing || ! in_array($listing->review_status, self::PENDING, true)
            || $listing->duplicate_check_status === 'confirmed_duplicate') return;

        $candidates = $this->assets->likelyDuplicates($listing);
        if ($candidates === [] || $candidates[0]['duplicate_detection_source'] === 'algorithm') return;
        $candidate = collect($candidates)->firstWhere('published', true) ?? $candidates[0];
        $previous = Property::query()->with(['images', 'propertyAsset'])->find($candidate['listing_id']);
        if (! $previous || ! $listing->images->first() || ! $previous->images->first()) return;

        $submissionId = $this->submissionId($listing);
        if ($submissionId === null || ($expectedSubmission !== null && $submissionId !== $expectedSubmission)) return;
        $listingFacts = $this->facts($listing);
        $previousFacts = $this->facts($previous);
        $fingerprints = [
            'listing' => $this->fingerprint($listing),
            'candidate' => $this->fingerprint($previous),
        ];

        $claim = DB::transaction(function () use ($listing, $submissionId): ?int {
            $locked = Property::query()->lockForUpdate()->find($listing->id);
            if (! $locked || ! in_array($locked->review_status, self::PENDING, true)
                || $this->submissionId($locked) !== $submissionId) return null;

            $last = $this->latestAssessment($locked, $submissionId);
            if ($last && ($last->action === self::FINISHED || $last->created_at->gt(now()->subMinutes(4)))) {
                return null;
            }

            return (int) $this->record($locked, self::STARTED)->id;
        });
        if ($claim === null) return;

        $signal = 'unavailable';
        try {
            $result = $this->gemini->comparePhotos(
                'Assess whether two real estate ads may depict the same physical property. '
                .'The first photo belongs to the submitted ad and the second belongs to the earlier candidate. '
                .'Consider distance, address similarity signals, property facts and specific visible details together. '
                .'A shared façade, building, neighborhood, floor plan, stock photo or decor alone is insufficient. '
                .'For units (apartments, offices, shops, floors), only distinctive matching interior details count. '
                .'If evidence is weak, conflicting, or the photos show only a shared building, return inconclusive. '
                .'Return the one allowed evidence label only.',
                [
                    'distance_m' => $candidate['distance_m'],
                    'facts_in_common' => $candidate['signals'],
                    'submitted_property' => $listingFacts,
                    'comparison_property' => $previousFacts,
                ],
                ['type' => 'object', 'additionalProperties' => false, 'properties' => [
                    'signal' => ['type' => 'string', 'enum' => [...array_keys(self::PHOTO_SIGNALS), 'inconclusive']],
                ], 'required' => ['signal']],
                $this->photo($listing->images->first()),
                $this->photo($previous->images->first()),
            );
            $reason = $result['signal'] ?? null;
            if (is_string($reason) && isset(self::PHOTO_SIGNALS[$reason])) {
                $signal = $reason === 'matching_property_features'
                    && ($listing->propertyAsset?->identity_kind === 'unit' || $previous->propertyAsset?->identity_kind === 'unit'
                        || in_array($listing->type, ['apartment', 'office', 'shop', 'floor'], true))
                    ? 'inconclusive' : $reason;
            } else {
                $signal = 'inconclusive';
            }
        } catch (\Throwable) {
            // A photo or provider failure leaves the existing human review intact.
        }

        DB::transaction(function () use ($listing, $submissionId, $previous, $claim, $fingerprints, $signal): void {
            $locked = Property::query()->with(['images', 'propertyAsset'])->lockForUpdate()->find($listing->id);
            if (! $locked || ! in_array($locked->review_status, self::PENDING, true)
                || $this->submissionId($locked) !== $submissionId
                || $this->latestAssessment($locked, $submissionId)?->id !== $claim) return;

            $comparison = $previous->fresh(['images', 'propertyAsset']);
            if (! $comparison || $this->fingerprint($locked) !== $fingerprints['listing']
                || $this->fingerprint($comparison) !== $fingerprints['candidate']) return;

            $this->record($locked, self::FINISHED, [
                'candidate_listing_id' => (int) $comparison->id,
                'candidate_main_image_id' => (int) $comparison->images->first()->id,
                'fingerprints' => $fingerprints,
                'signal' => $signal,
            ], self::PHOTO_SIGNALS[$signal] ?? null);
        });
    }

    public function evidence(Property $listing, array $likelyDuplicates): array
    {
        $top = $likelyDuplicates[0] ?? [];
        if ($likelyDuplicates !== [] && ($top['duplicate_detection_source'] ?? null) === null) {
            $submissionId = $this->submissionId($listing);
            $record = $submissionId === null ? null : $this->latestAssessment($listing, $submissionId);
            $metadata = $record?->metadata ?? [];
            $signal = $metadata['signal'] ?? null;
            if (isset(self::PHOTO_SIGNALS[$signal])
                && $this->fingerprint($listing) === ($metadata['fingerprints']['listing'] ?? null)) {
                foreach ($likelyDuplicates as &$candidate) {
                    if ($candidate['listing_id'] === ($metadata['candidate_listing_id'] ?? null)
                        && $candidate['main_image_id'] === ($metadata['candidate_main_image_id'] ?? null)) {
                        $current = Property::query()->with('images')->find($candidate['listing_id']);
                        if (! $current
                            || $this->fingerprint($current) !== ($metadata['fingerprints']['candidate'] ?? null)) break;

                        $candidate['duplicate_detection_source'] = 'ai';
                        $candidate['duplicate_detection_reason'] = self::PHOTO_SIGNALS[$signal];
                        $candidate['signals'][] = $signal;
                        $top = $candidate;
                        break;
                    }
                }
                unset($candidate);
            }
        }

        return [
            'duplicate_detection_source' => $top['duplicate_detection_source'] ?? null,
            'duplicate_detection_reason' => $top['duplicate_detection_reason'] ?? null,
            'duplicate_detection_signals' => $top['signals'] ?? [],
            'likely_duplicate_candidates' => $likelyDuplicates,
        ];
    }

    public function submissionId(Property $listing): ?int
    {
        $id = ListingReview::query()->where('listing_id', $listing->id)
            ->where('action', 'submitted')->latest('id')->value('id');

        return $id === null ? null : (int) $id;
    }

    private function latestAssessment(Property $listing, int $submissionId): ?ListingReview
    {
        return ListingReview::query()->where('listing_id', $listing->id)->where('id', '>', $submissionId)
            ->whereIn('action', [self::STARTED, self::FINISHED])->latest('id')->first();
    }

    private function record(Property $property, string $action, array $metadata = [], ?string $reason = null): ListingReview
    {
        return ListingReview::query()->create([
            'listing_id' => $property->id,
            'action' => $action,
            'from_review_status' => $property->review_status,
            'to_review_status' => $property->review_status,
            'reason' => $reason,
            'metadata' => $metadata,
            'created_at' => now(),
        ]);
    }

    private function facts(Property $property): array
    {
        return $property->only(['type', 'area_m2', 'bedrooms', 'bathrooms', 'has_parking']);
    }

    private function fingerprint(Property $property): string
    {
        $property->loadMissing('images');
        $image = $property->images->first();

        return hash('sha256', serialize([
            $this->facts($property),
            $property->only(['property_asset_id', 'address', 'latitude', 'longitude']),
            $image?->id,
            $image?->path,
        ]));
    }

    private function photo(PropertyImage $image): string
    {
        $path = (string) $image->path;
        if ($path === '') throw new RuntimeException('Listing photo unavailable.');

        // A PropertyImage may retain its original editor path after promotion.
        // Read only derivatives of attached listing photos, never draft records,
        // ownership documents, raw originals or external URLs.
        $bytes = $this->storage->readBytes(
            $this->images->variantPath($path, 'thumb'), true, self::PHOTO_READ_TIMEOUT_SECONDS,
        );
        if (strlen($bytes) > 256 * 1024 || (@getimagesizefromstring($bytes)[2] ?? null) !== IMAGETYPE_JPEG) {
            throw new RuntimeException('Listing photo unavailable.');
        }

        return $bytes;
    }
}
