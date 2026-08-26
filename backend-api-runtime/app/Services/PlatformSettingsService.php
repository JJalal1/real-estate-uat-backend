<?php
namespace App\Services;

use App\Models\PlatformSetting;

class PlatformSettingsService
{
    public const SAFE_KEYS = [
        'platform.name',
        'platform.contact_phone',
        'platform.contact_email',
        'listings.review_warning_hours',
        'support.sla_hours',
        'support.sla_warning_hours',
        'notifications.dashboard_alerts_enabled',
    ];

    public function get(string $key, mixed $default=null): mixed
    {
        if (! in_array($key,self::SAFE_KEYS,true)) return $default;
        $row=PlatformSetting::query()->where('key',$key)->first();
        if(!$row) return $default;
        return $this->typed($row->value,$row->value_type,$default);
    }

    public function safeRows(): array
    {
        return PlatformSetting::query()->whereIn('key',self::SAFE_KEYS)->orderBy('group_key')->orderBy('id')->get()->map(fn(PlatformSetting $row)=>[
            'key'=>$row->key,'value'=>$this->typed($row->value,$row->value_type,null),'value_type'=>$row->value_type,
            'group'=>$row->group_key,'label_ar'=>$row->label_ar,'updated_at'=>$row->updated_at?->toIso8601String(),
        ])->values()->all();
    }

    public function typed(?string $value,string $type,mixed $default=null): mixed
    {
        if($value===null) return $default;
        return match($type){
            'boolean'=>filter_var($value,FILTER_VALIDATE_BOOLEAN),
            'integer'=>(int)$value,
            default=>$value,
        };
    }
}
