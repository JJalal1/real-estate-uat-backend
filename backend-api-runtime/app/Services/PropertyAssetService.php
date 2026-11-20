<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\PropertyPublicationBlock;
use App\Models\User;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class PropertyAssetService
{
    public function resolveOrCreate(User $user, array $listing, ?int $requestedAssetId = null): PropertyAsset
    {
        if ($requestedAssetId !== null) {
            $asset = PropertyAsset::query()->findOrFail($requestedAssetId);
            $this->assertPurposeNotBlocked($asset, (string) $listing['purpose']);
            return $asset;
        }

        $hash = $this->identityHash($listing);
        $asset = PropertyAsset::query()->where('identity_hash', $hash)->first();
        if (! $asset) {
            $asset = PropertyAsset::query()->create([
                'created_by_user_id' => $user->id,
                'identity_hash' => $hash,
                'identity_version' => 1,
                'property_type' => (string) $listing['type'],
                'canonical_address' => $this->nullable($listing['address'] ?? null),
                'canonical_latitude' => (float) $listing['latitude'],
                'canonical_longitude' => (float) $listing['longitude'],
                'area_m2' => $listing['area_m2'] ?? null,
                'bedrooms' => $listing['bedrooms'] ?? null,
                'bathrooms' => $listing['bathrooms'] ?? null,
                'status' => 'active',
            ]);
        }
        $this->assertPurposeNotBlocked($asset, (string) $listing['purpose']);
        return $asset;
    }

    public function identityHash(array $listing): string
    {
        $address = Str::lower(trim(preg_replace('/\s+/u', ' ', (string) ($listing['address'] ?? '')) ?? ''));
        $parts = [
            'v1',
            Str::lower((string) ($listing['type'] ?? '')),
            number_format((float) ($listing['latitude'] ?? 0), 6, '.', ''),
            number_format((float) ($listing['longitude'] ?? 0), 6, '.', ''),
            (string) ($listing['area_m2'] ?? ''),
            (string) ($listing['bedrooms'] ?? ''),
            (string) ($listing['bathrooms'] ?? ''),
            $address,
        ];
        return hash('sha256', implode('|', $parts));
    }

    public function assertNotAlreadyPublished(PropertyAsset $asset, string $purpose, ?int $excludeListingId = null): void
    {
        $query = $asset->listings()->where('status', 'published')->whereNotIn('availability_status', ['sold','rented']);
        if ($excludeListingId !== null) {
            $query->where('id', '<>', $excludeListingId);
        }
        if ($query->exists()) {
            throw new ConflictHttpException('This physical property is already published. Duplicate publication is not allowed.');
        }
    }

    /**
     * Returns explainable duplicate candidates for human support review.
     *
     * This is deliberately advisory. Similarity alone never rejects a listing;
     * exact PropertyAsset publication rules remain the hard server boundary.
     */
    public function likelyDuplicates(Property $listing, int $limit = 5): array
    {
        if ($listing->latitude === null || $listing->longitude === null) {
            return [];
        }

        $latitude = (float) $listing->latitude;
        $longitude = (float) $listing->longitude;
        $latWindow = 0.003;
        $lonWindow = 0.003 / max(cos(deg2rad($latitude)), 0.25);
        $listing->loadMissing('propertyAsset');
        $identity = app(PropertyIdentityService::class);
        $identityMetadata = $listing->duplicate_check_metadata ?? [];
        $confirmed = $listing->duplicate_check_status === 'confirmed_duplicate'
            ? ($identityMetadata['candidate'] ?? null) : null;

        $candidates = Property::query()
            ->with(['propertyAsset', 'images'])
            ->whereKeyNot($listing->id)
            ->where(fn ($query) => $query->where('status', 'published')
                ->orWhereIn('review_status', ['submitted', 'under_review', 'approved']))
            ->where(function ($query) use ($listing, $confirmed, $latitude, $longitude, $latWindow, $lonWindow): void {
                $query->where(fn ($nearby) => $nearby->where('type', $listing->type)
                    ->whereBetween('latitude', [$latitude - $latWindow, $latitude + $latWindow])
                    ->whereBetween('longitude', [$longitude - $lonWindow, $longitude + $lonWindow]));
                $assetIds = array_filter([$listing->property_asset_id, $confirmed['property_asset_id'] ?? null]);
                if ($assetIds !== []) $query->orWhereIn('property_asset_id', $assetIds);
            })
            ->orderByRaw('CASE WHEN property_asset_id = ? THEN 0 ELSE 1 END', [$listing->property_asset_id])
            ->latest('id')
            ->limit(80)
            ->get();

        $results = [];
        foreach ($candidates as $candidate) {
            $sameAsset = $listing->property_asset_id !== null
                && (int) $candidate->property_asset_id === (int) $listing->property_asset_id;
            $confirmedMatch = $confirmed !== null
                && (isset($confirmed['listing_id'])
                    ? (int) $confirmed['listing_id'] === (int) $candidate->id
                    : (int) ($confirmed['property_asset_id'] ?? 0) === (int) $candidate->property_asset_id);
            if (! $sameAsset && ! $confirmedMatch
                && $identity->hasDistinctUnitIdentity($listing->propertyAsset, $candidate->propertyAsset)) {
                continue;
            }
            $distance = $this->distanceMeters(
                $latitude,
                $longitude,
                (float) $candidate->latitude,
                (float) $candidate->longitude,
            );
            if ($distance > 350 && ! $sameAsset && ! $confirmedMatch) {
                continue;
            }

            $score = 0;
            $signals = [];

            if ($sameAsset) {
                $score += 10;
                $signals[] = 'same_property_asset';
                if ($listing->propertyAsset?->identity_kind === 'unit') {
                    $signals[] = 'same_building_same_unit';
                }
            }

            if ($distance <= 30) {
                $score += 4;
                $signals[] = 'location_within_30m';
            } elseif ($distance <= 100) {
                $score += 3;
                $signals[] = 'location_within_100m';
            } elseif ($distance <= 250) {
                $score += 1;
                $signals[] = 'location_within_250m';
            }

            $addressScore = $this->addressSimilarity(
                (string) $listing->address,
                (string) $candidate->address,
            );
            if ($addressScore >= 0.98) {
                $score += 3;
                $signals[] = 'address_exact_normalized';
            } elseif ($addressScore >= 0.80) {
                $score += 2;
                $signals[] = 'address_high_similarity';
            } elseif ($addressScore >= 0.60) {
                $score += 1;
                $signals[] = 'address_partial_similarity';
            }

            $areaDelta = $this->relativeDelta($listing->area_m2, $candidate->area_m2);
            if ($areaDelta !== null && $areaDelta <= 0.05) {
                $score += 2;
                $signals[] = 'area_within_5_percent';
            } elseif ($areaDelta !== null && $areaDelta <= 0.10) {
                $score += 1;
                $signals[] = 'area_within_10_percent';
            }

            if ($listing->bedrooms !== null && $candidate->bedrooms !== null
                && (int) $listing->bedrooms === (int) $candidate->bedrooms) {
                $score += 1;
                $signals[] = 'bedrooms_equal';
            }

            if ($listing->bathrooms !== null && $candidate->bathrooms !== null
                && (int) $listing->bathrooms === (int) $candidate->bathrooms) {
                $score += 1;
                $signals[] = 'bathrooms_equal';
            }

            $strongMatch = $sameAsset || $confirmedMatch;
            if ($score < 5 && ! $strongMatch) {
                continue;
            }

            if ($confirmedMatch) {
                $signals = array_values(array_unique(array_merge($identityMetadata['signals'] ?? [], $signals)));
            }
            $results[] = [
                'listing_id' => (int) $candidate->id,
                'property_asset_id' => (int) $candidate->property_asset_id,
                'title' => (string) $candidate->title,
                'status' => (string) $candidate->status,
                'published' => $candidate->isPubliclyAvailable(),
                'review_status' => (string) $candidate->review_status,
                'distance_m' => (int) round($distance),
                'score' => $score,
                'signals' => $signals,
                'address' => $candidate->address,
                'area_m2' => $candidate->area_m2,
                'bedrooms' => $candidate->bedrooms,
                'bathrooms' => $candidate->bathrooms,
                'main_image_id' => $candidate->images->first()?->id,
                'duplicate_detection_source' => $strongMatch ? 'algorithm' : null,
                'duplicate_detection_reason' => $strongMatch ? $this->algorithmReason($signals) : null,
            ];
        }

        usort($results, function (array $a, array $b): int {
            return [$b['duplicate_detection_source'] !== null, $b['score'], -$b['distance_m'], $b['listing_id']]
                <=> [$a['duplicate_detection_source'] !== null, $a['score'], -$a['distance_m'], $a['listing_id']];
        });

        return array_slice($results, 0, max(1, min($limit, 20)));
    }

    private function algorithmReason(array $signals): string
    {
        return match (true) {
            in_array('same_building_same_unit', $signals, true) => 'تطابقت هوية المبنى والدور والوحدة.',
            in_array('same_property_asset', $signals, true),
            in_array('same_property_identity', $signals, true) => 'تطابقت هوية العقار المسجلة.',
            in_array('active_representation_exists', $signals, true) => 'يوجد إعلان مرتبط بتمثيل نشط للعقار نفسه.',
            in_array('land_overlap_85_percent', $signals, true) => 'تداخلت حدود الأرض بنسبة ٨٥٪ فأكثر.',
            in_array('same_explicit_house_reference', $signals, true) => 'تطابق رقم المبنى والعنوان وتقاربت المساحة والموقع.',
            default => 'تطابقت بيانات تعريف العقار.',
        };
    }

    public function activeBlock(PropertyAsset $asset, string $purpose): ?PropertyPublicationBlock
    {
        return PropertyPublicationBlock::query()
            ->where('property_asset_id', $asset->id)
            ->where('purpose', $purpose)
            ->where('is_active', true)
            ->latest('id')
            ->first();
    }

    public function assertPurposeNotBlocked(PropertyAsset $asset, string $purpose): void
    {
        if ($this->activeBlock($asset, $purpose)) {
            throw new ConflictHttpException('This physical property is blocked from publication for this purpose.');
        }
    }

    private function addressSimilarity(string $left, string $right): float
    {
        $a = $this->normalizedAddress($left);
        $b = $this->normalizedAddress($right);
        if ($a === '' || $b === '') {
            return 0.0;
        }
        if ($a === $b) {
            return 1.0;
        }
        similar_text($a, $b, $percent);
        return max(0.0, min(1.0, $percent / 100));
    }

    private function normalizedAddress(string $value): string
    {
        $text = mb_strtolower(trim($value));
        $text = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $text) ?? $text;
        $text = strtr($text, ['أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ى' => 'ي', 'ؤ' => 'و', 'ئ' => 'ي', 'ة' => 'ه']);
        $text = preg_replace('/[^\p{L}\p{N}]+/u', ' ', $text) ?? $text;
        return trim(preg_replace('/\s+/u', ' ', $text) ?? $text);
    }

    private function relativeDelta(mixed $left, mixed $right): ?float
    {
        if ($left === null || $right === null) {
            return null;
        }
        $a = (float) $left;
        $b = (float) $right;
        if ($a <= 0 || $b <= 0) {
            return null;
        }
        return abs($a - $b) / max($a, $b);
    }

    private function distanceMeters(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earth = 6371000.0;
        $phi1 = deg2rad($lat1);
        $phi2 = deg2rad($lat2);
        $deltaPhi = deg2rad($lat2 - $lat1);
        $deltaLambda = deg2rad($lon2 - $lon1);
        $a = sin($deltaPhi / 2) ** 2
            + cos($phi1) * cos($phi2) * sin($deltaLambda / 2) ** 2;
        return $earth * 2 * atan2(sqrt($a), sqrt(max(0.0, 1 - $a)));
    }

    private function nullable(mixed $value): ?string
    {
        $text = trim((string) $value);
        return $text === '' ? null : $text;
    }
}
