<?php
namespace App\Services;

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
                'created_by_user_id'=>$user->id,
                'identity_hash'=>$hash,
                'identity_version'=>1,
                'property_type'=>(string)$listing['type'],
                'canonical_address'=>$this->nullable($listing['address'] ?? null),
                'canonical_latitude'=>(float)$listing['latitude'],
                'canonical_longitude'=>(float)$listing['longitude'],
                'area_m2'=>$listing['area_m2'] ?? null,
                'bedrooms'=>$listing['bedrooms'] ?? null,
                'bathrooms'=>$listing['bathrooms'] ?? null,
                'status'=>'active',
            ]);
        }
        $this->assertPurposeNotBlocked($asset, (string) $listing['purpose']);
        return $asset;
    }

    public function identityHash(array $listing): string
    {
        $address = Str::lower(trim(preg_replace('/\s+/u', ' ', (string)($listing['address'] ?? '')) ?? ''));
        $parts = [
            'v1', Str::lower((string)($listing['type'] ?? '')),
            number_format((float)($listing['latitude'] ?? 0), 6, '.', ''),
            number_format((float)($listing['longitude'] ?? 0), 6, '.', ''),
            (string)($listing['area_m2'] ?? ''), (string)($listing['bedrooms'] ?? ''),
            (string)($listing['bathrooms'] ?? ''), $address,
        ];
        return hash('sha256', implode('|', $parts));
    }

    public function assertNotAlreadyPublished(PropertyAsset $asset, string $purpose, ?int $excludeListingId = null): void
    {
        $query=$asset->listings()->where('status','published');
        if($excludeListingId!==null)$query->where('id','<>',$excludeListingId);
        if($query->exists()){
            throw new ConflictHttpException('This physical property is already published. Duplicate publication is not allowed.');
        }
    }

    public function activeBlock(PropertyAsset $asset, string $purpose): ?PropertyPublicationBlock
    {
        return PropertyPublicationBlock::query()
            ->where('property_asset_id', $asset->id)->where('purpose', $purpose)->where('is_active', true)
            ->latest('id')->first();
    }

    public function assertPurposeNotBlocked(PropertyAsset $asset, string $purpose): void
    {
        if ($this->activeBlock($asset, $purpose)) {
            throw new ConflictHttpException('This physical property is blocked from publication for this purpose.');
        }
    }

    private function nullable(mixed $value): ?string
    {
        $text = trim((string)$value);
        return $text === '' ? null : $text;
    }
}
