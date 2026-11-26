<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\BrokerAvailabilityService;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $data=$request->validate([
            'page'=>['sometimes','integer','min:1'],
            'per_page'=>['sometimes','integer','between:1,200'],
            'platform_history'=>['sometimes','boolean'],
            'unread_only'=>['sometimes','boolean'],
        ]);
        $platformHistory = $request->boolean('platform_history');
        $query = $this->notificationsFor($user, $platformHistory, now());
        if ($platformHistory) {
            $unreadCount = (clone $query)->whereNull('read_at')->count();
            $query->latest('created_at');
        }
        if (!$platformHistory || $request->boolean('unread_only')) {
            $query->whereNull('read_at');
        }
        $page = $query->latest('id')
            ->paginate((int)($data['per_page']??200),['*'],'page',(int)($data['page']??1));
        $meta = [
            'current_page'=>$page->currentPage(),'last_page'=>$page->lastPage(),
            'per_page'=>$page->perPage(),'total'=>$page->total(),
        ];
        if ($platformHistory) {
            $meta['unread_count'] = $unreadCount;
        }
        return response()->json(['data'=>$page->getCollection()->map(fn(UserNotification $n)=>$this->data($n))->values(),'meta'=>$meta]);
    }
    public function unreadCount(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $request->validate(['platform_history'=>['sometimes','boolean']]);
        $count = $this->notificationsFor($user, $request->boolean('platform_history'), now())
            ->whereNull('read_at')->count();
        return response()->json(['data'=>['count'=>$count]]);
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

    public function readAllHistory(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $now = now();
        $count = $this->notificationsFor($user, true, $now)
            ->whereNull('read_at')->update(['read_at'=>$now]);
        return response()->json(['message'=>'Notifications marked read.','data'=>['updated'=>$count]]);
    }

    private function notificationsFor(User $user, bool $platformHistory, CarbonInterface $now): Builder
    {
        $query = UserNotification::query()->where('user_id', $user->id);
        if ($platformHistory) {
            $query->where('type', '<>', 'message_received')->where('created_at', '>=', $now->copy()->subDays(7));
        }
        return $query;
    }

    private function data(UserNotification $n): array
    {
        $isListingReminder = $n->type === 'broker_availability_due';
        return ['id'=>$n->id,'type'=>$n->type,
            'title'=>$isListingReminder ? BrokerAvailabilityService::REMINDER_TITLE : $n->title,
            'body'=>$isListingReminder ? BrokerAvailabilityService::REMINDER_BODY : $n->body,
            'entity_type'=>$n->entity_type,'entity_id'=>$n->entity_id,'data'=>$n->data,
            'read_at'=>$n->read_at?->toIso8601String(),'created_at'=>$n->created_at?->toIso8601String()];
    }
}
