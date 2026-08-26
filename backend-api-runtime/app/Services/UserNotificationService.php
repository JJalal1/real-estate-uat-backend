<?php
namespace App\Services;

use App\Models\UserNotification;

class UserNotificationService
{
    public function create(int $userId, string $type, string $title, ?string $body=null, ?string $entityType=null, ?int $entityId=null, array $data=[]): UserNotification
    {
        return UserNotification::query()->create([
            'user_id'=>$userId,'type'=>$type,'title'=>$title,'body'=>$body,
            'entity_type'=>$entityType,'entity_id'=>$entityId,'data'=>$data ?: null,'created_at'=>now(),
        ]);
    }
}
