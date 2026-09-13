<?php

namespace App\Services;

use App\Models\Property;
use App\Models\PropertyAsset;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class PropertyIdentityService
{
    private const UNIT_TYPES = ['apartment', 'office', 'shop'];
    private const CHECKABLE_STATES = ['submitted', 'under_review', 'approved'];

    public function resolveOrCreateAsset(User $actor, array $listing): PropertyAsset
    {
        $identity = $this->identityData($listing);
        $existing = $this->findExactAsset($identity);
        if ($existing) return $existing;

        try {
            $asset = PropertyAsset::query()->create([
                'created_by_user_id' => $actor->id,
                'identity_hash' => $identity['identity_hash'],
                'identity_version' => 2,
                'identity_kind' => $identity['identity_kind'],
                'property_type' => (string) $listing['type'],
                'canonical_address' => $this->nullable($listing['address'] ?? null),
                'canonical_address_normalized' => $identity['address_normalized'],
                'canonical_latitude' => (float) $listing['latitude'],
                'canonical_longitude' => (float) $listing['longitude'],
                'area_m2' => $listing['area_m2'] ?? null,
                'bedrooms' => $listing['bedrooms'] ?? null,
                'bathrooms' => $listing['bathrooms'] ?? null,
                'building_reference' => $identity['building_reference'],
                'building_identity_key' => $identity['building_identity_key'],
                'unit_identity_key' => $identity['unit_identity_key'],
                'unit_number' => $identity['unit_number'],
                'floor_number' => $identity['floor_number'],
                'land_boundary_geojson' => $identity['land_boundary_geojson'],
                'land_boundary_hash' => $identity['land_boundary_hash'],
                'status' => 'active',
            ]);
            $this->syncLandBoundaryGeometry($asset);
            return $asset;
        } catch (QueryException $e) {
            $raceWinner = $this->findExactAsset($identity);
            if ($raceWinner) return $raceWinner;
            throw $e;
        }
    }

    public function validateIdentityInput(array $listing): void
    {
        $type = (string) ($listing['type'] ?? '');
        $inputVersion = (int) ($listing['listing_input_version'] ?? 1);
        $errors = [];
        if ($inputVersion >= 3 && in_array($type, self::UNIT_TYPES, true)) {
            if (trim((string) ($listing['building_reference'] ?? '')) === '') {
                $errors['building_reference'][] = 'حدد اسم أو رقم المبنى حتى نميز الوحدة عن العقارات المجاورة.';
            }
            if (trim((string) ($listing['unit_number'] ?? '')) === '') {
                $errors['unit_number'][] = 'رقم الوحدة مطلوب للشقق والمكاتب والمحلات لمنع تكرار نفس الوحدة.';
            }
        }
        if ($type === 'land') {
            try {
                $this->normalizeBoundary($listing['land_boundary_geojson'] ?? null);
            } catch (ValidationException $e) {
                $errors = array_merge_recursive($errors, $e->errors());
            }
        }
        if ($errors !== []) throw ValidationException::withMessages($errors);
    }

    /**
     * Returns one of: distinct, possible_duplicate, confirmed_duplicate.
     */
    public function evaluate(Property $listing, ?User $actor = null, bool $persist = true): array
    {
        $listing->loadMissing('propertyAsset');
        $asset = $listing->propertyAsset;
        if (! $asset) {
            throw new ConflictHttpException('تعذر تحديد هوية العقار. احفظ بيانات العقار مرة أخرى ثم أعد المحاولة.');
        }

        $activeClaim = DB::table('property_representation_claims')
            ->where('property_asset_id', $asset->id)
            ->where('status', 'active')
            ->first();
        if ($activeClaim && (int) $activeClaim->advertiser_user_id !== (int) $listing->user_id) {
            return $this->finishEvaluation($listing, $actor, [
                'decision' => 'confirmed_duplicate',
                'score' => 100,
                'signals' => ['active_representation_exists'],
                'candidate' => $this->candidatePayload(Property::query()->find($activeClaim->property_id), 0, false),
            ], $persist);
        }

        $sameAsset = Property::query()
            ->whereKeyNot($listing->id)
            ->where('property_asset_id', $asset->id)
            ->where(function ($q): void {
                $q->where('status', 'published')->orWhereIn('review_status', self::CHECKABLE_STATES);
            })
            ->orderByRaw("CASE WHEN status = 'published' THEN 0 ELSE 1 END")
            ->latest('id')
            ->first();
        if ($sameAsset) {
            return $this->finishEvaluation($listing, $actor, [
                'decision' => 'confirmed_duplicate',
                'score' => 100,
                'signals' => ['same_property_identity'],
                'candidate' => $this->candidatePayload($sameAsset, $this->distanceBetween($listing, $sameAsset), true),
            ], $persist);
        }

        $kind = (string) ($asset->identity_kind ?: $this->kindForType((string) $listing->type));
        if ($kind === 'unit') {
            $result = $this->evaluateUnit($listing, $asset);
        } elseif ($kind === 'land') {
            $result = $this->evaluateLand($listing, $asset);
        } else {
            $result = $this->evaluateStandalone($listing);
        }

        return $this->finishEvaluation($listing, $actor, $result, $persist);
    }

    public function recordSelfVerification(User $actor, Property $listing, string $differenceType, string $note): array
    {
        if ((int) $listing->user_id !== (int) $actor->id) abort(403);
        $first = $this->evaluate($listing, $actor, true);
        if ($first['decision'] === 'confirmed_duplicate') {
            throw new ConflictHttpException('هذا العقار أو هذه الوحدة مسجلة بالفعل على المنصة ولا يمكن إنشاء إعلان آخر لها.');
        }
        if ($first['decision'] === 'distinct') return $first;

        $verification = [
            'version' => 1,
            'assertion' => 'different_property',
            'difference_type' => $differenceType,
            'note' => trim($note),
            'candidate_property_id' => $first['candidate']['listing_id'] ?? null,
            'accepted_at' => now()->toIso8601String(),
            'user_id' => (int) $actor->id,
        ];
        $listing->forceFill(['duplicate_self_verification' => $verification])->save();
        $result = $this->evaluate($listing->fresh('propertyAsset'), $actor, true);
        if ($result['decision'] === 'possible_duplicate') {
            $listing->forceFill(['duplicate_check_status' => 'needs_support'])->save();
            $result['status'] = 'needs_support';
            $result['message'] = 'ما زال التشابه مرتفعاً بعد التحقق الذاتي؛ سيُرسل الإعلان للمراجعة مع المقارنة الجاهزة.';
        }
        return $result;
    }

    public function assertSubmissionAllowed(User $actor, Property $listing): array
    {
        $result = $this->evaluate($listing, $actor, true);
        if ($result['decision'] === 'confirmed_duplicate') {
            throw new ConflictHttpException('هذا العقار أو هذه الوحدة مسجلة بالفعل على المنصة ولا يمكن إنشاء إعلان آخر لها.');
        }
        if ($result['decision'] === 'possible_duplicate' && empty($listing->duplicate_self_verification)) {
            throw ValidationException::withMessages([
                'duplicate_self_verification' => ['وجدنا عقاراً مشابهاً جداً بالقرب من هذا الموقع. أكد أنه عقار مختلف وأدخل سبب الاختلاف قبل الإرسال.'],
            ]);
        }
        return $result;
    }

    public function assertApprovalAllowed(User $reviewer, Property $listing, ?string $supportReason = null): array
    {
        $result = $this->evaluate($listing, $reviewer, true);
        if ($result['decision'] === 'confirmed_duplicate') {
            throw new ConflictHttpException('لا يمكن اعتماد الإعلان لأنه يطابق عقاراً أو وحدة مسجلة بالفعل.');
        }
        if ($result['decision'] === 'possible_duplicate') {
            $reason = trim((string) $supportReason);
            if ($listing->duplicate_check_status !== 'needs_support' || mb_strlen($reason) < 10) {
                throw ValidationException::withMessages([
                    'duplicate_review_reason' => ['الحالة ما زالت مشتبهة. راجع مقارنة الهوية وسجل سبب اعتبار العقار مختلفاً قبل الاعتماد.'],
                ]);
            }
        }
        return $result;
    }

    public function ensureRepresentation(Property $listing): void
    {
        DB::transaction(function () use ($listing): void {
            $existing = DB::table('property_representation_claims')
                ->where('property_asset_id', $listing->property_asset_id)
                ->where('status', 'active')
                ->lockForUpdate()
                ->first();
            if ($existing) {
                if ((int) $existing->advertiser_user_id !== (int) $listing->user_id) {
                    throw new ConflictHttpException('يوجد ممثل نشط لهذا العقار على المنصة. لا يمكن إنشاء تمثيل موازٍ للعقار نفسه.');
                }
                DB::table('property_representation_claims')->where('id', $existing->id)->update([
                    'property_id' => $listing->id,
                    'purpose' => $listing->purpose,
                    'updated_at' => now(),
                ]);
                return;
            }
            DB::table('property_representation_claims')->insert([
                'property_asset_id' => $listing->property_asset_id,
                'property_id' => $listing->id,
                'advertiser_user_id' => $listing->user_id,
                'purpose' => $listing->purpose,
                'status' => 'active',
                'started_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });
    }

    public function transferRepresentation(User $actor, Property $listing, string $reason): void
    {
        DB::transaction(function () use ($actor, $listing, $reason): void {
            $current = DB::table('property_representation_claims')
                ->where('property_asset_id', $listing->property_asset_id)
                ->where('status', 'active')
                ->lockForUpdate()
                ->first();
            if ($current && (int) $current->advertiser_user_id === (int) $listing->user_id) return;
            if ($current) {
                DB::table('property_representation_claims')->where('id', $current->id)->update([
                    'status' => 'ended',
                    'ended_at' => now(),
                    'end_reason' => trim($reason),
                    'updated_at' => now(),
                ]);
            }
            DB::table('property_representation_claims')->insert([
                'property_asset_id' => $listing->property_asset_id,
                'property_id' => $listing->id,
                'advertiser_user_id' => $listing->user_id,
                'purpose' => $listing->purpose,
                'status' => 'active',
                'started_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('property_identity_checks')->insert([
                'property_id' => $listing->id,
                'candidate_property_id' => $current?->property_id,
                'candidate_property_asset_id' => $listing->property_asset_id,
                'actor_user_id' => $actor->id,
                'result' => 'representation_transferred',
                'score' => 100,
                'signals' => json_encode(['manual_authorized_transfer'], JSON_UNESCAPED_UNICODE),
                'metadata' => json_encode(['reason' => trim($reason), 'from_user_id' => $current?->advertiser_user_id, 'to_user_id' => $listing->user_id], JSON_UNESCAPED_UNICODE),
                'created_at' => now(),
            ]);
        });
    }

    public function releaseRepresentationForListing(Property $listing, string $reason = 'listing_removed'): void
    {
        DB::table('property_representation_claims')
            ->where('property_asset_id', $listing->property_asset_id)
            ->where('property_id', $listing->id)
            ->where('status', 'active')
            ->update(['status' => 'ended', 'ended_at' => now(), 'end_reason' => $reason, 'updated_at' => now()]);
    }

    private function evaluateUnit(Property $listing, PropertyAsset $asset): array
    {
        if (! $asset->building_identity_key || ! $asset->unit_identity_key) {
            return ['decision' => 'possible_duplicate', 'score' => 70, 'signals' => ['unit_identity_incomplete'], 'candidate' => null];
        }
        $otherAssetIds = PropertyAsset::query()
            ->where('id', '<>', $asset->id)
            ->where('status', 'active')
            ->where('building_identity_key', $asset->building_identity_key)
            ->where('unit_identity_key', $asset->unit_identity_key)
            ->pluck('id');
        if ($otherAssetIds->isNotEmpty()) {
            $candidate = Property::query()->whereIn('property_asset_id', $otherAssetIds)
                ->where(function ($q): void { $q->where('status', 'published')->orWhereIn('review_status', self::CHECKABLE_STATES); })
                ->latest('id')->first();
            if ($candidate) return ['decision' => 'confirmed_duplicate', 'score' => 100, 'signals' => ['same_building_same_unit'], 'candidate' => $this->candidatePayload($candidate, $this->distanceBetween($listing, $candidate), true)];
        }
        return ['decision' => 'distinct', 'score' => 0, 'signals' => ['unit_identity_unique'], 'candidate' => null];
    }

    private function evaluateLand(Property $listing, PropertyAsset $asset): array
    {
        $candidates = $this->nearbyCandidates($listing, 400);
        $best = null;
        foreach ($candidates as $candidate) {
            $candidateAsset = $candidate->propertyAsset;
            if (! $candidateAsset || $candidateAsset->identity_kind !== 'land') continue;
            $distance = $this->distanceBetween($listing, $candidate);
            $overlap = $this->landOverlapRatio($asset, $candidateAsset);
            $areaDelta = $this->relativeDelta($listing->area_m2, $candidate->area_m2);
            $signals = [];
            $score = 0;
            if ($overlap !== null) {
                if ($overlap >= 0.85) { $score += 90; $signals[] = 'land_overlap_85_percent'; }
                elseif ($overlap >= 0.50) { $score += 65; $signals[] = 'land_overlap_50_percent'; }
                elseif ($overlap >= 0.20) { $score += 40; $signals[] = 'land_overlap_20_percent'; }
                else { $signals[] = 'land_boundaries_distinct'; }
            }
            if ($areaDelta !== null && $areaDelta <= 0.05) { $score += 10; $signals[] = 'area_within_5_percent'; }
            elseif ($areaDelta !== null && $areaDelta <= 0.12) { $score += 6; $signals[] = 'area_within_12_percent'; }
            if ($distance <= 40) { $score += 8; $signals[] = 'location_within_40m'; }
            elseif ($distance <= 120) { $score += 4; $signals[] = 'location_within_120m'; }

            $decision = ($overlap !== null && $overlap >= 0.85 && ($areaDelta === null || $areaDelta <= 0.12))
                ? 'confirmed_duplicate'
                : (($overlap !== null && $overlap >= 0.20) || ($overlap === null && $score >= 14) ? 'possible_duplicate' : 'distinct');
            $row = ['decision' => $decision, 'score' => min(100, $score), 'signals' => $signals, 'candidate' => $this->candidatePayload($candidate, $distance, $decision === 'confirmed_duplicate')];
            if ($best === null || $row['score'] > $best['score']) $best = $row;
        }
        return $best ?? ['decision' => 'distinct', 'score' => 0, 'signals' => ['no_similar_land_boundary'], 'candidate' => null];
    }

    private function evaluateStandalone(Property $listing): array
    {
        $best = null;
        foreach ($this->nearbyCandidates($listing, 350) as $candidate) {
            $distance = $this->distanceBetween($listing, $candidate);
            $addressSimilarity = $this->addressSimilarity((string) $listing->address, (string) $candidate->address);
            $areaDelta = $this->relativeDelta($listing->area_m2, $candidate->area_m2);
            $score = 0; $signals = [];
            if ($distance <= 25) { $score += 5; $signals[] = 'location_within_25m'; }
            elseif ($distance <= 60) { $score += 4; $signals[] = 'location_within_60m'; }
            elseif ($distance <= 120) { $score += 2; $signals[] = 'location_within_120m'; }
            elseif ($distance <= 250) { $score += 1; $signals[] = 'location_within_250m'; }
            if ($addressSimilarity >= 0.96) { $score += 4; $signals[] = 'address_exact_normalized'; }
            elseif ($addressSimilarity >= 0.80) { $score += 3; $signals[] = 'address_high_similarity'; }
            elseif ($addressSimilarity >= 0.60) { $score += 1; $signals[] = 'address_partial_similarity'; }
            if ($areaDelta !== null && $areaDelta <= 0.05) { $score += 3; $signals[] = 'area_within_5_percent'; }
            elseif ($areaDelta !== null && $areaDelta <= 0.10) { $score += 2; $signals[] = 'area_within_10_percent'; }
            elseif ($areaDelta !== null && $areaDelta <= 0.20) { $score += 1; $signals[] = 'area_within_20_percent'; }
            if ($listing->bedrooms !== null && $candidate->bedrooms !== null && (int) $listing->bedrooms === (int) $candidate->bedrooms) { $score++; $signals[] = 'bedrooms_equal'; }
            if ($listing->bathrooms !== null && $candidate->bathrooms !== null && (int) $listing->bathrooms === (int) $candidate->bathrooms) { $score++; $signals[] = 'bathrooms_equal'; }
            if ($listing->building_facade && $candidate->building_facade && $listing->building_facade === $candidate->building_facade) { $score++; $signals[] = 'facade_equal'; }

            $independentHighConfidence = $distance <= 60 && $addressSimilarity >= 0.80 && $areaDelta !== null && $areaDelta <= 0.10;
            $decision = $independentHighConfidence && $score >= 11 ? 'confirmed_duplicate' : ($score >= 7 ? 'possible_duplicate' : 'distinct');
            $row = ['decision' => $decision, 'score' => min(100, $score * 8), 'signals' => $signals, 'candidate' => $this->candidatePayload($candidate, $distance, $decision === 'confirmed_duplicate')];
            if ($best === null || $row['score'] > $best['score']) $best = $row;
        }
        return $best ?? ['decision' => 'distinct', 'score' => 0, 'signals' => ['no_similar_nearby_property'], 'candidate' => null];
    }

    private function nearbyCandidates(Property $listing, int $meters): iterable
    {
        $latitude = (float) $listing->latitude;
        $longitude = (float) $listing->longitude;
        $latWindow = $meters / 111320;
        $lonWindow = $latWindow / max(cos(deg2rad($latitude)), 0.25);
        return Property::query()->with('propertyAsset')
            ->whereKeyNot($listing->id)
            ->where('type', $listing->type)
            ->where(function ($q): void { $q->where('status', 'published')->orWhereIn('review_status', self::CHECKABLE_STATES); })
            ->whereBetween('latitude', [$latitude - $latWindow, $latitude + $latWindow])
            ->whereBetween('longitude', [$longitude - $lonWindow, $longitude + $lonWindow])
            ->latest('id')->limit(100)->get()
            ->filter(fn (Property $candidate) => $this->distanceBetween($listing, $candidate) <= $meters);
    }

    private function finishEvaluation(Property $listing, ?User $actor, array $result, bool $persist): array
    {
        $result['status'] = match ($result['decision']) {
            'confirmed_duplicate' => 'confirmed_duplicate',
            'possible_duplicate' => empty($listing->duplicate_self_verification) ? 'self_verification_required' : 'needs_support',
            default => 'distinct',
        };
        $result['message'] = match ($result['status']) {
            'confirmed_duplicate' => 'هذا العقار أو هذه الوحدة مسجلة بالفعل على المنصة.',
            'self_verification_required' => 'وجدنا عقاراً مشابهاً جداً. أكد أنه مختلف قبل الإرسال.',
            'needs_support' => 'بقيت حالة تشابه غير محسومة وستذهب للمراجعة الاستثنائية.',
            default => 'لم نجد تكراراً يمنع النشر.',
        };
        if (! $persist) return $result;

        $listing->forceFill([
            'duplicate_check_status' => $result['status'],
            'duplicate_check_score' => (int) $result['score'],
            'duplicate_check_metadata' => ['signals' => $result['signals'], 'candidate' => $result['candidate']],
            'duplicate_checked_at' => now(),
        ])->save();
        DB::table('property_identity_checks')->insert([
            'property_id' => $listing->id,
            'candidate_property_id' => $result['candidate']['listing_id'] ?? null,
            'candidate_property_asset_id' => $result['candidate']['property_asset_id'] ?? null,
            'actor_user_id' => $actor?->id,
            'result' => $result['status'],
            'score' => (int) $result['score'],
            'signals' => json_encode($result['signals'], JSON_UNESCAPED_UNICODE),
            'metadata' => json_encode(['candidate' => $result['candidate']], JSON_UNESCAPED_UNICODE),
            'created_at' => now(),
        ]);
        return $result;
    }

    private function identityData(array $listing): array
    {
        $this->validateIdentityInput($listing);
        $type = (string) $listing['type'];
        $kind = $this->kindForType($type);
        $inputVersion = (int) ($listing['listing_input_version'] ?? 1);
        if (
            $kind === 'unit'
            && $inputVersion < 3
            && (
                trim((string) ($listing['building_reference'] ?? '')) === ''
                || trim((string) ($listing['unit_number'] ?? '')) === ''
            )
        ) {
            // Legacy v1/v2 clients did not send unit identity fields. Preserve
            // their contract while v3+ uses the stricter unit identity model.
            $kind = 'standalone';
        }
        $address = $this->normalizedText((string) ($listing['address'] ?? ''));
        $buildingReference = $kind === 'unit' ? $this->normalizedText((string) ($listing['building_reference'] ?? '')) : null;
        $unitNumber = $kind === 'unit' ? $this->normalizedText((string) ($listing['unit_number'] ?? '')) : null;
        $floorNumber = $kind === 'unit' ? $this->normalizedText((string) ($listing['floor_number'] ?? '')) : null;
        $buildingKey = $kind === 'unit' ? hash('sha256', $address.'|'.$buildingReference) : null;
        $unitKey = $kind === 'unit' ? hash('sha256', ($floorNumber ?? '').'|'.$unitNumber) : null;
        $boundary = $kind === 'land' ? $this->normalizeBoundary($listing['land_boundary_geojson'] ?? null) : null;
        $boundaryJson = $boundary ? json_encode($boundary, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null;
        $boundaryHash = $boundaryJson ? hash('sha256', $boundaryJson) : null;
        $identityHash = match ($kind) {
            'unit' => hash('sha256', 'v2|unit|'.$buildingKey.'|'.$unitKey),
            'land' => hash('sha256', 'v2|land|'.($boundaryHash ?: $this->pointIdentity($listing, $address))),
            default => hash('sha256', 'v2|standalone|'.$this->pointIdentity($listing, $address)),
        };
        return [
            'identity_kind' => $kind,
            'identity_hash' => $identityHash,
            'address_normalized' => $address ?: null,
            'building_reference' => $buildingReference,
            'building_identity_key' => $buildingKey,
            'unit_identity_key' => $unitKey,
            'unit_number' => $unitNumber,
            'floor_number' => $floorNumber,
            'land_boundary_geojson' => $boundary,
            'land_boundary_hash' => $boundaryHash,
        ];
    }

    private function findExactAsset(array $identity): ?PropertyAsset
    {
        if ($identity['identity_kind'] === 'unit') {
            return PropertyAsset::query()->where('status', 'active')->where('building_identity_key', $identity['building_identity_key'])->where('unit_identity_key', $identity['unit_identity_key'])->first();
        }
        if ($identity['identity_kind'] === 'land' && $identity['land_boundary_hash']) {
            return PropertyAsset::query()->where('status', 'active')->where('land_boundary_hash', $identity['land_boundary_hash'])->first();
        }
        return PropertyAsset::query()->where('status', 'active')->where('identity_hash', $identity['identity_hash'])->first();
    }

    private function normalizeBoundary(mixed $value): ?array
    {
        if ($value === null || $value === '' || $value === []) return null;
        if (is_string($value)) {
            $decoded = json_decode($value, true);
            if (! is_array($decoded)) throw ValidationException::withMessages(['land_boundary_geojson' => ['حدود الأرض غير صالحة.']]);
            $value = $decoded;
        }
        $coordinates = $value['type'] ?? null;
        if ($coordinates === 'Feature') $value = $value['geometry'] ?? [];
        if (($value['type'] ?? null) !== 'Polygon' || ! is_array($value['coordinates'] ?? null) || ! is_array($value['coordinates'][0] ?? null)) {
            throw ValidationException::withMessages(['land_boundary_geojson' => ['حدد حدود الأرض كمضلع واضح على الخريطة.']]);
        }
        $ring = [];
        foreach ($value['coordinates'][0] as $point) {
            if (! is_array($point) || count($point) < 2 || ! is_numeric($point[0]) || ! is_numeric($point[1])) continue;
            $lon = round((float) $point[0], 6); $lat = round((float) $point[1], 6);
            if ($lat < -90 || $lat > 90 || $lon < -180 || $lon > 180) continue;
            if ($ring === [] || $ring[array_key_last($ring)] !== [$lon, $lat]) $ring[] = [$lon, $lat];
        }
        if (count($ring) > 1 && $ring[0] === $ring[array_key_last($ring)]) array_pop($ring);
        if (count($ring) < 3) throw ValidationException::withMessages(['land_boundary_geojson' => ['حدد ثلاث زوايا على الأقل لحدود الأرض.']]);

        $forward = $this->rotateRing($ring);
        $reverse = $this->rotateRing(array_reverse($ring));
        $canonical = json_encode($forward) <= json_encode($reverse) ? $forward : $reverse;
        $canonical[] = $canonical[0];
        return ['type' => 'Polygon', 'coordinates' => [$canonical]];
    }

    private function rotateRing(array $ring): array
    {
        $keys = array_map(fn (array $p) => sprintf('%012.6f,%011.6f', $p[0] + 180, $p[1] + 90), $ring);
        $minIndex = array_search(min($keys), $keys, true);
        return array_merge(array_slice($ring, $minIndex), array_slice($ring, 0, $minIndex));
    }

    private function syncLandBoundaryGeometry(PropertyAsset $asset): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql' || ! $asset->land_boundary_geojson) return;
        $json = json_encode($asset->land_boundary_geojson, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $valid = DB::selectOne('SELECT ST_IsValid(ST_SetSRID(ST_GeomFromGeoJSON(?),4326)) AS valid', [$json]);
        if (! ($valid->valid ?? false)) throw ValidationException::withMessages(['land_boundary_geojson' => ['حدود الأرض تتقاطع أو غير صالحة هندسياً.']]);
        DB::statement('UPDATE property_assets SET land_boundary = ST_SetSRID(ST_GeomFromGeoJSON(?),4326) WHERE id = ?', [$json, $asset->id]);
    }

    private function landOverlapRatio(PropertyAsset $left, PropertyAsset $right): ?float
    {
        if (! $left->land_boundary_geojson || ! $right->land_boundary_geojson) return null;
        if (DB::connection()->getDriverName() === 'pgsql') {
            $row = DB::selectOne('SELECT CASE WHEN LEAST(ST_Area(a.land_boundary::geography), ST_Area(b.land_boundary::geography)) <= 0 THEN 0 ELSE ST_Area(ST_Intersection(a.land_boundary,b.land_boundary)::geography) / LEAST(ST_Area(a.land_boundary::geography), ST_Area(b.land_boundary::geography)) END AS ratio FROM property_assets a, property_assets b WHERE a.id=? AND b.id=?', [$left->id, $right->id]);
            return isset($row->ratio) ? (float) $row->ratio : null;
        }
        return $this->bboxOverlapRatio($left->land_boundary_geojson, $right->land_boundary_geojson);
    }

    private function bboxOverlapRatio(array $a, array $b): float
    {
        $box = function (array $polygon): array {
            $ring = $polygon['coordinates'][0] ?? [];
            $xs = array_column($ring, 0); $ys = array_column($ring, 1);
            return [min($xs), min($ys), max($xs), max($ys)];
        };
        [$ax1,$ay1,$ax2,$ay2] = $box($a); [$bx1,$by1,$bx2,$by2] = $box($b);
        $intersection = max(0, min($ax2,$bx2)-max($ax1,$bx1)) * max(0, min($ay2,$by2)-max($ay1,$by1));
        $minArea = min(max(0,($ax2-$ax1)*($ay2-$ay1)), max(0,($bx2-$bx1)*($by2-$by1)));
        return $minArea > 0 ? $intersection / $minArea : 0.0;
    }

    private function candidatePayload(?Property $candidate, float $distance, bool $showIdentity): ?array
    {
        if (! $candidate) return null;
        $published = $candidate->status === 'published';
        return [
            'listing_id' => $published ? (int) $candidate->id : null,
            'property_asset_id' => (int) $candidate->property_asset_id,
            'published' => $published,
            'title' => $published ? (string) $candidate->title : 'عقار مشابه قيد المعالجة',
            'type' => (string) $candidate->type,
            'distance_m' => (int) round($distance),
            'area_m2' => $showIdentity ? $candidate->area_m2 : null,
        ];
    }

    private function pointIdentity(array $listing, string $address): string
    {
        return implode('|', [
            Str::lower((string) ($listing['type'] ?? '')),
            number_format((float) ($listing['latitude'] ?? 0), 6, '.', ''),
            number_format((float) ($listing['longitude'] ?? 0), 6, '.', ''),
            (string) ($listing['area_m2'] ?? ''),
            (string) ($listing['bedrooms'] ?? ''),
            (string) ($listing['bathrooms'] ?? ''),
            $address,
        ]);
    }

    private function kindForType(string $type): string
    {
        if ($type === 'land') return 'land';
        if (in_array($type, self::UNIT_TYPES, true)) return 'unit';
        return 'standalone';
    }

    private function addressSimilarity(string $left, string $right): float
    {
        $a = $this->normalizedText($left); $b = $this->normalizedText($right);
        if ($a === '' || $b === '') return 0.0;
        if ($a === $b) return 1.0;
        similar_text($a, $b, $percent);
        return max(0.0, min(1.0, $percent / 100));
    }

    private function normalizedText(string $value): string
    {
        $text = mb_strtolower(trim($value));
        $text = preg_replace('/[\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $text) ?? $text;
        $text = strtr($text, ['أ'=>'ا','إ'=>'ا','آ'=>'ا','ى'=>'ي','ؤ'=>'و','ئ'=>'ي','ة'=>'ه']);
        $text = preg_replace('/[^\p{L}\p{N}]+/u', ' ', $text) ?? $text;
        return trim(preg_replace('/\s+/u', ' ', $text) ?? $text);
    }

    private function relativeDelta(mixed $left, mixed $right): ?float
    {
        if ($left === null || $right === null) return null;
        $a=(float)$left; $b=(float)$right;
        if ($a<=0 || $b<=0) return null;
        return abs($a-$b)/max($a,$b);
    }

    private function distanceBetween(Property $a, Property $b): float
    {
        $earth=6371000.0; $lat1=deg2rad((float)$a->latitude); $lat2=deg2rad((float)$b->latitude);
        $dLat=deg2rad((float)$b->latitude-(float)$a->latitude); $dLon=deg2rad((float)$b->longitude-(float)$a->longitude);
        $h=sin($dLat/2)**2+cos($lat1)*cos($lat2)*sin($dLon/2)**2;
        return $earth*2*atan2(sqrt($h),sqrt(max(0.0,1-$h)));
    }

    private function nullable(mixed $value): ?string
    {
        $text=trim((string)$value); return $text===''?null:$text;
    }
}
