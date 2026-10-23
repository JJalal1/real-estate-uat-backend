<?php

namespace App\Services;

use Illuminate\Validation\ValidationException;

/** Listing-only contact policy. Auth/OTP identities are never normalized here. */
class ListingContactService
{
    public function policy(): array
    {
        return ['country_code'=>'967','local_length'=>9,'prefixes'=>config('listing_contacts.yemen_mobile_prefixes') ?: ['70','71','73','77','78']];
    }

    public function normalize(?string $value, string $field, bool $required = false): ?string
    {
        $value=trim(strtr($value ?? '',array_combine(preg_split('//u','٠١٢٣٤٥٦٧٨٩',-1,PREG_SPLIT_NO_EMPTY),str_split('0123456789'))));
        $value=preg_replace('/[\s()\-]/u','',$value);
        if (str_starts_with($value,'+967')) $value=substr($value,4);
        elseif (str_starts_with($value,'00967')) $value=substr($value,5);
        if ($value==='' && !$required) return null;
        if (!preg_match('/^7[0-9]{8}$/D',$value) || !in_array(substr($value,0,2),$this->policy()['prefixes'],true)) {
            throw ValidationException::withMessages([$field=>['أدخل رقم جوال يمني من 9 أرقام يبدأ ببادئة معتمدة.']]);
        }
        return $value;
    }
}
