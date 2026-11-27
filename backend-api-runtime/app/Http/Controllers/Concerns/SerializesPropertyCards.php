<?php

namespace App\Http\Controllers\Concerns;

use App\Models\Property;
use App\Models\PropertyImage;
use Illuminate\Http\Request;

trait SerializesPropertyCards
{
    private function summaryData(Property $property, Request $request): array
    {
        $property->loadMissing('images');
        $mainImage = $property->images->first();

        $data = [
            'id' => $property->id,
            'title' => $property->title,
            'purpose' => $property->purpose,
            'type' => $property->type,
            'unit_occupies_entire_floor' => $property->type === 'floor' || (bool) $property->unit_occupies_entire_floor,
            'tenure_type' => $property->tenure_type,
            'price' => (float) $property->price,
            'currency' => $property->currency,
            'area_m2' => $property->area_m2,
            'area_value' => $property->area_value !== null ? (float) $property->area_value : ($property->area_m2 !== null ? (float) $property->area_m2 : null),
            'area_unit' => $property->area_unit ?? ($property->area_m2 !== null ? 'sqm' : null),
            'bedrooms' => $property->bedrooms,
            'bathrooms' => $property->bathrooms,
            'has_parking' => $property->has_parking,
            'has_elevator' => null,
            'floors_count' => $property->floors_count,
            'units_per_floor' => $property->units_per_floor,
            'shop_openings' => $property->shop_openings,
            'building_facade' => $property->building_facade,
            'address' => $property->address,
            'latitude' => (float) $property->latitude,
            'longitude' => (float) $property->longitude,
            'status' => $property->status === 'published' && !$property->isPubliclyAvailable() ? 'unavailable' : $property->status,
            'published_at' => $property->published_at?->toIso8601String(),
            'availability_status' => $property->availability_status ?? 'available',
            'availability_confirmed_at' => $property->availability_confirmed_at?->toIso8601String(),
            'availability_due_at' => $property->availability_due_at?->toIso8601String(),
            'view_count' => (int) $property->view_count,
            'main_image' => $mainImage ? $this->imageUrl($mainImage, $request, 'card') : null,
            'image_urls' => $property->images->take(12)->map(fn ($image) => $this->imageUrl($image, $request, 'card'))->values(),
            'image_count' => $property->images->count(),
            'floor_number' => in_array($property->type, ['apartment', 'floor', 'office', 'shop'], true) ? $property->floor_number : null,
            'is_spotlight' => $property->isPubliclyAvailable() && $property->spotlight_until?->isFuture() === true,
        ];
        return array_intersect_key(app(\App\Services\DynamicPropertySchema::class)->facts($data,true),$data);
    }

    private function imageUrl(PropertyImage $image, Request $request, ?string $variant = null): string
    {
        $raw = trim((string) $image->cdn_url);
        if ($raw !== '') {
            if (str_starts_with($raw, 'http://') || str_starts_with($raw, 'https://')) {
                return $raw;
            }
            return rtrim($request->getSchemeAndHttpHost(), '/') . '/' . ltrim($raw, '/');
        }

        return rtrim($request->getSchemeAndHttpHost(), '/') . '/api/property-media/' . $image->id . ($variant ? '?variant='.$variant : '').(config('listing_media.watermark.enabled') ? ($variant ? '&' : '?').'v='.app(\App\Services\ListingWatermarkService::class)->version() : '');
    }

    protected function publicPriceData(Property $property, ?object $term): array
    {
        $saiAmount=0.0;$sai=null;$note=null;$displayPrice=(float)$property->price;
        if($term){
            $basis=$property->purpose==='rent'?(float)($property->monthly_rent?:0):(float)$property->price;
            $fixed = ($term->sai_amount_type ?? 'percentage') === 'fixed';
            if($fixed)$saiAmount=round((float)$term->fixed_sai_amount,2);
            elseif($basis>0)$saiAmount=round($basis*((float)$term->sai_rate_percent/100),2);
            $buyerPays=in_array($term->payer,['buyer','tenant'],true);
            $displayMode=$property->price_display_mode ?: ($buyerPays?'excludes_sai':null);
            if($buyerPays){
                if($displayMode==='includes_sai'){$displayPrice=round((float)$property->price+$saiAmount,2);$note='المبلغ شامل السعي';}
                else $note='المبلغ غير شامل السعي';
            }
            if ((int) $property->listing_input_version >= 6) {
                $displayPrice = (float) $property->price;
                $note = $fixed ? 'السعي '.$saiAmount.' '.$term->fixed_sai_currency : 'السعي '.(float) $term->sai_rate_percent.'%';
            }
            $sai=['rate_percent'=>$fixed?null:(float)$term->sai_rate_percent,'payer'=>$term->payer,'amount'=>$saiAmount,
                'amount_type'=>$fixed?'fixed':'percentage','fixed_amount'=>$fixed?$saiAmount:null,
                'currency'=>$fixed?$term->fixed_sai_currency:$property->currency];
        }
        return [
            'base_price'=>(float)$property->price,'display_price'=>$displayPrice,'price_display_mode'=>$property->price_display_mode ?: (($term&&in_array($term->payer,['buyer','tenant'],true))?'excludes_sai':null),
            'price_display_note'=>$note,'monthly_rent'=>$property->monthly_rent!==null?(float)$property->monthly_rent:null,
            'rental_term_months'=>$property->rental_term_months,'advance_months'=>$property->advance_months,'sai'=>$sai,
        ];
    }
}
