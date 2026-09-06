<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Models\PropertyRequest;
use App\Models\PropertySuggestion;
use App\Models\User;
use App\Services\PropertyRequestService;
use App\Services\AuditLogService;
use App\Services\UserNotificationService;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class PropertyRequestController extends Controller
{
    private const TYPES = ['apartment','house','villa','land','shop','office','farm'];

    public function __construct(private readonly PropertyRequestService $service, private readonly UserNotificationService $notifications, private readonly AuditLogService $audit) {}

    public function index(Request $request): JsonResponse
    {
        $this->service->expireDue();
        $rows=PropertyRequest::query()->where('requester_user_id',$request->user()->id)->withCount('suggestions')->latest('id')->limit(200)->get();
        return response()->json(['data'=>$rows->map(fn(PropertyRequest $row)=>$this->data($row))->values()]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated=$request->validate($this->rules());
        $validated['currency']=strtoupper($validated['currency']);
        $validated=array_merge($validated,$this->service->resolveLocation($validated));
        $row=PropertyRequest::query()->create(array_merge($validated,[
            'requester_user_id'=>$request->user()->id,'status'=>'active',
            'expires_at'=>now()->addDays((int)$validated['active_duration_days']),
        ]));
        $this->audit->record($request->user(),'property_request.created',$row,['status'=>'active'],$request,$request->user()->id);
        return response()->json(['message'=>'Property request created.','data'=>$this->data($row)],201);
    }

    public function show(Request $request, PropertyRequest $propertyRequest): JsonResponse
    {
        $this->service->expireDue();$propertyRequest->refresh();
        $this->owner($request->user(),$propertyRequest);
        $propertyRequest->load(['suggestions.property.images']);
        return response()->json(['data'=>$this->data($propertyRequest,true)]);
    }

    public function update(Request $request, PropertyRequest $propertyRequest): JsonResponse
    {
        $validated=$request->validate($this->rules());
        $validated['currency']=strtoupper($validated['currency']);
        $validated=array_merge($validated,$this->service->resolveLocation($validated));
        $propertyRequest=DB::transaction(function()use($request,$propertyRequest,$validated){
            $locked=PropertyRequest::query()->whereKey($propertyRequest->id)->lockForUpdate()->firstOrFail();
            $this->owner($request->user(),$locked);abort_unless($locked->status==='active'&&$locked->expires_at->isFuture(),409,'Only active requests can be edited.');
            $locked->fill($validated)->forceFill(['expires_at'=>now()->addDays((int)$validated['active_duration_days'])])->save();
            return $locked;
        });
        $this->audit->record($request->user(),'property_request.updated',$propertyRequest,['fields'=>array_keys($validated)],$request,$request->user()->id);
        return response()->json(['message'=>'Property request updated.','data'=>$this->data($propertyRequest)]);
    }

    public function close(Request $request, PropertyRequest $propertyRequest): JsonResponse
    {
        $propertyRequest=DB::transaction(function()use($request,$propertyRequest){
            $locked=PropertyRequest::query()->whereKey($propertyRequest->id)->lockForUpdate()->firstOrFail();
            $this->owner($request->user(),$locked);abort_unless(in_array($locked->status,['active','matched'],true)&&$locked->expires_at->isFuture(),409,'This request can no longer be closed.');
            $locked->forceFill(['status'=>'closed','closed_at'=>now()])->save();return $locked;
        });
        $this->audit->record($request->user(),'property_request.closed',$propertyRequest,[],$request,$request->user()->id);
        return response()->json(['message'=>'Property request closed.','data'=>$this->data($propertyRequest)]);
    }

    public function researcherIndex(Request $request): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->researcher($user);$this->service->expireDue();
        $rows=$this->service->matchingRequests($user);
        return response()->json(['data'=>$rows->map(fn(PropertyRequest $row)=>$this->data($row))->values()]);
    }

    public function researcherShow(Request $request, PropertyRequest $propertyRequest): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->researcher($user);$this->service->expireDue();$propertyRequest->refresh();
        abort_unless(in_array($propertyRequest->status,['active','matched'],true)&&$propertyRequest->expires_at->isFuture(),404);
        $properties=$this->service->eligibleProperties($user,$propertyRequest);
        abort_if($properties->isEmpty(),404);
        return response()->json(['data'=>array_merge($this->data($propertyRequest),['eligible_properties'=>$properties->map(fn(Property $p)=>$this->propertyData($p))->values()])]);
    }

    public function suggest(Request $request, PropertyRequest $propertyRequest): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->researcher($user);
        $validated=$request->validate(['property_id'=>['required','integer','exists:properties,id'],'note'=>['nullable','string','max:1000']]);
        try {
            $suggestion=DB::transaction(function()use($propertyRequest,$validated,$user,$request){
                $locked=PropertyRequest::query()->whereKey($propertyRequest->id)->lockForUpdate()->firstOrFail();
                abort_unless(in_array($locked->status,['active','matched'],true)&&$locked->expires_at->isFuture(),409,'Only current requests accept suggestions.');
                $property=Property::query()->whereKey($validated['property_id'])->where('user_id',$user->id)->where('status','published')->where('review_status','approved')->first();
                abort_unless($property&&$this->service->eligibleProperties($user,$locked)->contains('id',$property->id),422,'The property is not eligible for this request.');
                $row=PropertySuggestion::query()->create(['property_request_id'=>$locked->id,'property_id'=>$property->id,'suggested_by_user_id'=>$user->id,'suggested_by_name_snapshot'=>$user->name,'note'=>$validated['note']??null]);
                if($locked->status==='active')$locked->forceFill(['status'=>'matched','matched_at'=>now()])->save();
                $this->notifications->create($locked->requester_user_id,'property_suggestion','اقتراح عقار جديد','تم اقتراح عقار يطابق طلبك.','property_suggestion',$row->id,['property_request_id'=>$locked->id,'property_id'=>$property->id]);
                $this->audit->record($user,'property_suggestion.created',$row,['property_request_id'=>$locked->id,'property_id'=>$property->id],$request,$locked->requester_user_id);
                return $row->load('property.images');
            });
        } catch (QueryException $e) {
            if(in_array((string)$e->getCode(),['23000','23505'],true)
                && str_contains($e->getMessage(),'property_request_property_suggestion_unique'))abort(409,'This property has already been suggested for the request.');
            throw $e;
        }
        return response()->json(['message'=>'Property suggested.','data'=>$this->suggestionData($suggestion)],201);
    }

    private function rules(): array { return [
        'operation_type'=>['required',Rule::in(['sale','rent'])],'property_type'=>['required',Rule::in(self::TYPES)],
        'governorate_id'=>['nullable','integer','exists:governorates,id'],'geo_cell_id'=>['nullable','integer','exists:geo_cells,id'],
        'governorate'=>['required','string','max:120'],'district'=>['required','string','max:120'],'area'=>['nullable','string','max:160'],
        'budget_min'=>['required','numeric','min:0'],'budget_max'=>['required','numeric','gte:budget_min'],'currency'=>['required','string','size:3','regex:/^[A-Za-z]{3}$/'],
        'requested_area_min'=>['nullable','integer','min:1'],'requested_area_max'=>['nullable','integer','gte:requested_area_min'],'rooms'=>['nullable','integer','min:1','max:100'],
        'additional_specifications'=>['nullable','string','max:4000'],'active_duration_days'=>['required','integer','min:1','max:180'],
    ]; }
    private function owner(User $user,PropertyRequest $row): void { abort_unless((int)$row->requester_user_id===(int)$user->id,404); }
    private function researcher(User $user): void { abort_unless($this->service->isEligibleResearcher($user),403); }
    private function data(PropertyRequest $r,bool $withSuggestions=false): array {
        $data=['id'=>$r->id,'governorate_id'=>$r->governorate_id,'geo_cell_id'=>$r->geo_cell_id,'operation_type'=>$r->operation_type,'property_type'=>$r->property_type,'governorate'=>$r->governorate,'district'=>$r->district,'area'=>$r->area,'budget_min'=>$r->budget_min,'budget_max'=>$r->budget_max,'currency'=>$r->currency,'requested_area_min'=>$r->requested_area_min,'requested_area_max'=>$r->requested_area_max,'rooms'=>$r->rooms,'additional_specifications'=>$r->additional_specifications,'active_duration_days'=>$r->active_duration_days,'status'=>$r->status,'expires_at'=>$r->expires_at?->toIso8601String(),'suggestions_count'=>$r->suggestions_count??$r->suggestions()->count(),'created_at'=>$r->created_at?->toIso8601String()];
        if($withSuggestions)$data['suggestions']=$r->suggestions->map(fn(PropertySuggestion $s)=>$this->suggestionData($s))->values();return $data;
    }
    private function suggestionData(PropertySuggestion $s): array { return ['id'=>$s->id,'property_request_id'=>$s->property_request_id,'property_id'=>$s->property_id,'suggested_by_name'=>$s->suggested_by_name_snapshot,'note'=>$s->note,'property'=>$this->propertyData($s->property),'created_at'=>$s->created_at?->toIso8601String()]; }
    private function propertyData(Property $p): array { return ['id'=>$p->id,'title'=>$p->title,'purpose'=>$p->purpose,'type'=>$p->type,'price'=>(float)$p->price,'currency'=>$p->currency,'area_m2'=>$p->area_m2,'bedrooms'=>$p->bedrooms,'address'=>$p->address,'status'=>$p->status]; }
}
