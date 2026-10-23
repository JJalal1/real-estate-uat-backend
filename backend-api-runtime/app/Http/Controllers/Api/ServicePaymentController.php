<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PaymentEvent;
use App\Models\Property;
use App\Models\ServiceEntitlement;
use App\Models\ServiceOffering;
use App\Models\ServiceOrder;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ServicePaymentController extends Controller
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
    ) {}

    public function catalog(): JsonResponse
    {
        $rows=ServiceOffering::query()->where('is_active',true)->where('price_amount','>',0)->orderBy('sort_order')->orderBy('id')->get();
        return response()->json(['data'=>$rows->map(fn(ServiceOffering $offer)=>$this->offeringData($offer))->values()]);
    }

    public function propertyServices(Property $property): JsonResponse
    {
        abort_unless($property->status==='published' && $property->review_status==='approved',404);
        $rows=ServiceEntitlement::query()->where('target_type','property')->where('target_id',$property->id)->where('status','active')
            ->where(function($q){$q->whereNull('ends_at')->orWhere('ends_at','>',now());})->orderBy('ends_at')->get();
        return response()->json(['data'=>$rows->map(fn(ServiceEntitlement $e)=>$this->entitlementData($e))->values()]);
    }

    public function mineOrders(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=ServiceOrder::query()->where('user_id',$user->id)->with('entitlement')->orderByDesc('id')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(ServiceOrder $o)=>$this->orderData($o,$user))->values()]);
    }

    public function mineEntitlements(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=ServiceEntitlement::query()->where('user_id',$user->id)->orderByDesc('id')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(ServiceEntitlement $e)=>$this->entitlementData($e))->values()]);
    }

    public function showOrder(Request $request, ServiceOrder $order): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$order->user_id===(int)$user->id || $user->hasPermission('payments.manage'),404);
        $order->load(['entitlement','events']);
        return response()->json(['data'=>$this->orderData($order,$user,true)]);
    }

    public function createOrder(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $data=$request->validate(['offering_id'=>['required','integer'],'target_id'=>['nullable','integer','min:1']]);
        $offering=ServiceOffering::query()->whereKey($data['offering_id'])->where('is_active',true)->firstOrFail();
        abort_if((float)$offering->price_amount<=0,409,'This service is not commercially configured yet.');
        [$targetId,$targetTitle]=$this->resolveTarget($user,$offering,$data['target_id']??null);
        $active=ServiceEntitlement::query()->where('user_id',$user->id)->where('service_code',$offering->code)
            ->where('target_type',$offering->target_type)->where('target_id',$targetId)->where('status','active')
            ->where(function($q){$q->whereNull('ends_at')->orWhere('ends_at','>',now());})->exists();
        abort_if($active,409,'An active entitlement already exists for this service and target.');
        $pending=ServiceOrder::query()->where('user_id',$user->id)->where('service_code_snapshot',$offering->code)
            ->where('target_type',$offering->target_type)->where('target_id',$targetId)->where('status','pending')->exists();
        abort_if($pending,409,'A pending order already exists for this service and target.');

        $order=DB::transaction(function()use($request,$user,$offering,$targetId,$targetTitle){
            $order=ServiceOrder::query()->create([
                'reference'=>$this->newReference(),'user_id'=>$user->id,'user_name_snapshot'=>$user->name,
                'service_offering_id'=>$offering->id,'service_code_snapshot'=>$offering->code,
                'service_name_snapshot'=>$offering->name_ar,'target_type'=>$offering->target_type,'target_id'=>$targetId,
                'target_title_snapshot'=>$targetTitle,'duration_days_snapshot'=>$offering->duration_days,
                'amount'=>$offering->price_amount,'currency'=>strtoupper($offering->currency),'status'=>'pending',
            ]);
            $this->event($order,$user,'order_created',null,null,$order->amount,$order->currency,['service_code'=>$offering->code]);
            $this->audit->record($user,'service_order_created',$order,['service_code'=>$offering->code,'target_type'=>$offering->target_type,'amount'=>$order->amount,'currency'=>$order->currency],$request,$user->id);
            return $order;
        });
        return response()->json(['data'=>$this->orderData($order->load('entitlement'),$user)],201);
    }

    public function cancelOrder(Request $request, ServiceOrder $order): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$order->user_id===(int)$user->id,404);
        abort_unless($order->status==='pending',409,'Only pending orders can be cancelled.');
        DB::transaction(function()use($request,$user,$order){
            $order->forceFill(['status'=>'cancelled','cancelled_at'=>now()])->save();
            $this->event($order,$user,'order_cancelled');
            $this->audit->record($user,'service_order_cancelled',$order,[],$request,$user->id);
        });
        return response()->json(['data'=>$this->orderData($order->fresh('entitlement'),$user)]);
    }

    public function adminOffers(): JsonResponse
    {
        $rows=ServiceOffering::query()->orderBy('sort_order')->orderBy('id')->get();
        return response()->json(['data'=>$rows->map(fn(ServiceOffering $offer)=>$this->offeringData($offer))->values()]);
    }

    public function storeOffering(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $data=$request->validate([
            'code'=>['required','string','regex:/^[a-z0-9_]{3,64}$/','unique:service_offerings,code'],
            'name_ar'=>['required','string','max:160'],'name_en'=>['required','string','max:160'],
            'description_ar'=>['nullable','string','max:4000'],'description_en'=>['nullable','string','max:4000'],
            'target_type'=>['required','in:account,property'],'duration_days'=>['nullable','integer','min:1','max:3650'],
            'price_amount'=>['required','numeric','min:0','max:999999999999.99'],'currency'=>['required','string','regex:/^[A-Za-z]{3}$/'],
            'is_active'=>['required','boolean'],'sort_order'=>['nullable','integer','min:-100000','max:100000'],
        ]);
        $data['currency']=strtoupper($data['currency']);
        $data['sort_order']=$data['sort_order']??0;
        abort_if((bool)$data['is_active'] && (float)$data['price_amount']<=0,422,'Active services require a positive price.');
        $offer=ServiceOffering::query()->create($data+['created_by_user_id'=>$user->id,'created_by_name_snapshot'=>$user->name]);
        $this->audit->record($user,'service_offering_created',$offer,['code'=>$offer->code,'target_type'=>$offer->target_type,'is_active'=>$offer->is_active],$request);
        return response()->json(['data'=>$this->offeringData($offer)],201);
    }

    public function updateOffering(Request $request, ServiceOffering $offering): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $data=$request->validate([
            'name_ar'=>['sometimes','required','string','max:160'],'name_en'=>['sometimes','required','string','max:160'],
            'description_ar'=>['sometimes','nullable','string','max:4000'],'description_en'=>['sometimes','nullable','string','max:4000'],
            'duration_days'=>['sometimes','nullable','integer','min:1','max:3650'],
            'price_amount'=>['sometimes','required','numeric','min:0','max:999999999999.99'],
            'currency'=>['sometimes','required','string','regex:/^[A-Za-z]{3}$/'],'is_active'=>['sometimes','required','boolean'],
            'sort_order'=>['sometimes','integer','min:-100000','max:100000'],
        ]);
        if(isset($data['currency'])) $data['currency']=strtoupper($data['currency']);
        $nextPrice=array_key_exists('price_amount',$data)?(float)$data['price_amount']:(float)$offering->price_amount;
        $nextActive=array_key_exists('is_active',$data)?(bool)$data['is_active']:(bool)$offering->is_active;
        abort_if($nextActive && $nextPrice<=0,422,'Active services require a positive price.');
        $offering->forceFill($data)->save();
        $this->audit->record($user,'service_offering_updated',$offering,['code'=>$offering->code,'price_amount'=>$offering->price_amount,'currency'=>$offering->currency,'is_active'=>$offering->is_active],$request);
        return response()->json(['data'=>$this->offeringData($offering->fresh())]);
    }

    public function adminOrders(Request $request): JsonResponse
    {
        $status=$request->query('status');
        $q=ServiceOrder::query()->with('entitlement');
        if(is_string($status) && in_array($status,['pending','paid','cancelled','refunded'],true)) $q->where('status',$status);
        $rows=$q->orderByDesc('id')->limit(300)->get();
        /** @var User $user */ $user=$request->user();
        return response()->json(['data'=>$rows->map(fn(ServiceOrder $o)=>$this->orderData($o,$user))->values()]);
    }

    public function settle(Request $request, ServiceOrder $order): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $data=$request->validate([
            'provider'=>['required','in:manual_admin,bank_transfer,external_gateway'],
            'provider_reference'=>['required','string','min:3','max:120'],
        ]);
        $provider=$data['provider'];$providerReference=trim($data['provider_reference']);
        $order=DB::transaction(function()use($request,$actor,$order,$provider,$providerReference){
            $locked=ServiceOrder::query()->whereKey($order->id)->lockForUpdate()->firstOrFail();
            abort_unless($locked->status==='pending',409,'Only pending orders can be settled.');
            abort_if(ServiceOrder::query()->where('payment_provider',$provider)->where('payment_reference',$providerReference)->where('id','<>',$locked->id)->exists(),409,'This provider payment reference is already recorded.');
            $now=now();
            $locked->forceFill(['status'=>'paid','payment_provider'=>$provider,'payment_reference'=>$providerReference,'paid_at'=>$now])->save();
            $entitlement=ServiceEntitlement::query()->create([
                'service_order_id'=>$locked->id,'user_id'=>$locked->user_id,'service_code'=>$locked->service_code_snapshot,
                'service_name_snapshot'=>$locked->service_name_snapshot,'target_type'=>$locked->target_type,'target_id'=>$locked->target_id,
                'target_title_snapshot'=>$locked->target_title_snapshot,'starts_at'=>$now,
                'ends_at'=>$locked->duration_days_snapshot ? $now->copy()->addDays($locked->duration_days_snapshot) : null,
                'status'=>'active','granted_at'=>$now,
            ]);
            $this->event($locked,$actor,'payment_settled',$provider,$providerReference,$locked->amount,$locked->currency);
            $this->event($locked,$actor,'entitlement_activated',$provider,$providerReference,null,null,['entitlement_id'=>$entitlement->id]);
            $this->audit->record($actor,'service_payment_settled',$locked,['provider'=>$provider,'amount'=>$locked->amount,'currency'=>$locked->currency],$request,$locked->user_id);
            $this->notifications->create($locked->user_id,'service_payment_confirmed','تم تأكيد دفع الخدمة','تم تفعيل '.$locked->service_name_snapshot,'service_order',$locked->id,['reference'=>$locked->reference]);
            return $locked;
        });
        return response()->json(['data'=>$this->orderData($order->fresh(['entitlement','events']),$actor,true)]);
    }

    public function refund(Request $request, ServiceOrder $order): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $data=$request->validate(['reason'=>['required','string','min:3','max:1500']]);
        $order=DB::transaction(function()use($request,$actor,$order,$data){
            $locked=ServiceOrder::query()->whereKey($order->id)->lockForUpdate()->firstOrFail();
            abort_unless($locked->status==='paid',409,'Only paid orders can be refunded.');
            $now=now();$locked->forceFill(['status'=>'refunded','refunded_at'=>$now])->save();
            $entitlement=ServiceEntitlement::query()->where('service_order_id',$locked->id)->first();
            if($entitlement && $entitlement->status==='active'){
                $entitlement->forceFill(['status'=>'revoked','revoked_at'=>$now])->save();
                $this->event($locked,$actor,'entitlement_revoked',$locked->payment_provider,$locked->payment_reference,null,null,['entitlement_id'=>$entitlement->id]);
            }
            $this->event($locked,$actor,'payment_refunded',$locked->payment_provider,$locked->payment_reference,$locked->amount,$locked->currency,['reason'=>$data['reason']]);
            $this->audit->record($actor,'service_payment_refunded',$locked,['provider'=>$locked->payment_provider,'amount'=>$locked->amount,'currency'=>$locked->currency,'reason'=>$data['reason']],$request,$locked->user_id);
            $this->notifications->create($locked->user_id,'service_payment_refunded','تم تسجيل استرداد الخدمة','تم إلغاء تفعيل '.$locked->service_name_snapshot,'service_order',$locked->id,['reference'=>$locked->reference]);
            return $locked;
        });
        return response()->json(['data'=>$this->orderData($order->fresh(['entitlement','events']),$actor,true)]);
    }

    private function resolveTarget(User $user, ServiceOffering $offering, mixed $requestedTargetId): array
    {
        if($offering->target_type==='account') return [$user->id,$user->name];
        $targetId=(int)$requestedTargetId;abort_if($targetId<1,422,'A target listing is required for this service.');
        $property=Property::query()->whereKey($targetId)->where('user_id',$user->id)->where('status','published')->where('review_status','approved')->first();
        abort_unless($property,404);
        return [$property->id,$property->title];
    }

    private function newReference(): string
    {
        do{$reference='S14'.now()->format('ymd').Str::upper(Str::random(10));}while(ServiceOrder::query()->where('reference',$reference)->exists());
        return $reference;
    }

    private function event(ServiceOrder $order, ?User $actor, string $event, ?string $provider=null, ?string $providerReference=null, mixed $amount=null, ?string $currency=null, array $metadata=[]): PaymentEvent
    {
        return PaymentEvent::query()->create([
            'service_order_id'=>$order->id,'actor_user_id'=>$actor?->id,'actor_name_snapshot'=>$actor?->name,'event'=>$event,
            'provider'=>$provider,'provider_reference'=>$providerReference,'amount'=>$amount,'currency'=>$currency,
            'metadata'=>$metadata ?: null,'created_at'=>now(),
        ]);
    }

    private function offeringData(ServiceOffering $offer): array
    {
        return [
            'id'=>$offer->id,'code'=>$offer->code,'name_ar'=>$offer->name_ar,'name_en'=>$offer->name_en,
            'description_ar'=>$offer->description_ar,'description_en'=>$offer->description_en,'target_type'=>$offer->target_type,
            'duration_days'=>$offer->duration_days,'price_amount'=>$offer->price_amount,'currency'=>$offer->currency,
            'is_active'=>(bool)$offer->is_active,'sort_order'=>$offer->sort_order,
        ];
    }

    private function orderData(ServiceOrder $order, User $viewer, bool $includeEvents=false): array
    {
        $entitlement=$order->relationLoaded('entitlement') ? $order->entitlement : null;
        $data=[
            'id'=>$order->id,'reference'=>$order->reference,'user_id'=>$order->user_id,'user_name'=>$order->user_name_snapshot,
            'service_code'=>$order->service_code_snapshot,'service_name'=>$order->service_name_snapshot,
            'target_type'=>$order->target_type,'target_id'=>$order->target_id,'target_title'=>$order->target_title_snapshot,
            'duration_days'=>$order->duration_days_snapshot,'amount'=>$order->amount,'currency'=>$order->currency,'status'=>$order->status,
            'payment_provider'=>$order->payment_provider,'payment_reference'=>$order->payment_reference,
            'paid_at'=>$order->paid_at?->toISOString(),'cancelled_at'=>$order->cancelled_at?->toISOString(),'refunded_at'=>$order->refunded_at?->toISOString(),
            'created_at'=>$order->created_at?->toISOString(),'can_cancel'=>(int)$order->user_id===(int)$viewer->id && $order->status==='pending',
            'can_settle'=>$viewer->hasPermission('payments.manage') && $order->status==='pending',
            'can_refund'=>$viewer->hasPermission('payments.manage') && $order->status==='paid',
            'entitlement'=>$entitlement ? $this->entitlementData($entitlement) : null,
        ];
        if($includeEvents && $order->relationLoaded('events')){
            $data['events']=$order->events->map(fn(PaymentEvent $e)=>[
                'id'=>$e->id,'event'=>$e->event,'actor_name'=>$e->actor_name_snapshot,'provider'=>$e->provider,
                'provider_reference'=>$e->provider_reference,'amount'=>$e->amount,'currency'=>$e->currency,'metadata'=>$e->metadata,
                'created_at'=>$e->created_at?->toISOString(),
            ])->values();
        }
        return $data;
    }

    private function entitlementData(ServiceEntitlement $e): array
    {
        $active=$e->status==='active' && ($e->ends_at===null || $e->ends_at->isFuture());
        return [
            'id'=>$e->id,'service_order_id'=>$e->service_order_id,'service_code'=>$e->service_code,
            'service_name'=>$e->service_name_snapshot,'target_type'=>$e->target_type,'target_id'=>$e->target_id,
            'target_title'=>$e->target_title_snapshot,'starts_at'=>$e->starts_at?->toISOString(),'ends_at'=>$e->ends_at?->toISOString(),
            'status'=>$e->status,'is_active'=>$active,'granted_at'=>$e->granted_at?->toISOString(),'revoked_at'=>$e->revoked_at?->toISOString(),
        ];
    }
}
