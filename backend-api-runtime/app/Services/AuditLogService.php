<?php
namespace App\Services;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class AuditLogService
{
    private const SENSITIVE_KEY_PARTS = ['password','token','authorization','code','secret'];

    public function record(
        ?User $actor,
        string $action,
        ?Model $subject = null,
        array $metadata = [],
        ?Request $request = null,
        ?int $targetUserId = null,
    ): AuditLog {
        if (($request?->headers->get('X-Stage7-Smoke') || $request?->headers->get('X-Stage8-Smoke') || $request?->headers->get('X-Stage9-Smoke') || $request?->headers->get('X-Stage10-Smoke') || $request?->headers->get('X-Stage11-Smoke') || $request?->headers->get('X-Stage12-Smoke') || $request?->headers->get('X-Stage13-Smoke') || $request?->headers->get('X-Stage14-Smoke')) && app()->environment('local','testing')) {
            $metadata['system_test'] = true;
        }
        return AuditLog::query()->create([
            'actor_user_id'=>$actor?->id,
            'actor_name_snapshot'=>$actor?->name,
            'target_user_id'=>$targetUserId,
            'action'=>$action,
            'subject_type'=>$subject ? class_basename($subject) : null,
            'subject_id'=>$subject?->getKey(),
            'request_method'=>$request?->method(),
            'request_path'=>$request?->path(),
            'ip_address'=>$request?->ip(),
            'request_id'=>$request?->headers->get('X-Request-Id') ?: (string) Str::uuid(),
            'metadata'=>$this->sanitize($metadata),
            'created_at'=>now(),
        ]);
    }

    public function loginFingerprint(string $login): string
    {
        return hash('sha256', Str::lower(trim($login)));
    }

    private function sanitize(array $metadata): array
    {
        $clean=[];
        foreach ($metadata as $key=>$value) {
            $normalizedKey=Str::lower((string)$key);
            if (collect(self::SENSITIVE_KEY_PARTS)->contains(fn(string $part): bool => str_contains($normalizedKey,$part))) continue;
            if (is_array($value)) $value=$this->sanitize($value);
            if (is_string($value) && strlen($value)>1000) $value=substr($value,0,1000);
            $clean[$key]=$value;
        }
        return $clean;
    }
}
