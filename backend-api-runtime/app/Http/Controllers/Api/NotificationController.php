<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\UserNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=UserNotification::query()->where('user_id',$user->id)->latest('id')->limit(200)->get();
        return response()->json(['data'=>$rows->map(fn(UserNotification $n)=>$this->data($n))->values()]);
    }
    public function unreadCount(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        return response()->json(['data'=>['count'=>UserNotification::query()->where('user_id',$user->id)->whereNull('read_at')->count()]]);
    }
    public function read(Request $request, UserNotification $notification): JsonResponse
    {
        /** @var User $user */ $user=$request->user();abort_unless((int)$notification->user_id===(int)$user->id,404);
        if(!$notification->read_at)$notification->forceFill(['read_at'=>now()])->save();
        return response()->json(['message'=>'Notification marked read.','data'=>$this->data($notification)]);
    }
    public function readAll(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $count=UserNotification::query()->where('user_id',$user->id)->whereNull('read_at')->update(['read_at'=>now()]);
        return response()->json(['message'=>'Notifications marked read.','data'=>['updated'=>$count]]);
    }
    private function data(UserNotification $n): array
    {
        return ['id'=>$n->id,'type'=>$n->type,'title'=>$n->title,'body'=>$n->body,'entity_type'=>$n->entity_type,'entity_id'=>$n->entity_id,'data'=>$n->data,'read_at'=>$n->read_at?->toIso8601String(),'created_at'=>$n->created_at?->toIso8601String()];
    }
}
