<?php

namespace App\Http\Controllers\Api;

use App\Models\Property;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use App\Services\ListingWorkflowService;
use App\Services\PropertyAssetService;
use App\Services\PropertyFinancialService;
use App\Services\RegionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class FinancialPropertyController extends PropertyController
{
    public function __construct(
        private readonly ApiTokenService $financialTokens,
        AuditLogService $audit,
        CloudAssetStorageService $storage,
        RegionService $regions,
        PropertyAssetService $assets,
        ListingWorkflowService $workflow,
        private readonly PropertyFinancialService $finance,
    ) {
        parent::__construct($financialTokens,$audit,$storage,$regions,$assets,$workflow);
    }

    public function index(Request $request): JsonResponse { return $this->enrich(parent::index($request),$request,true); }
    public function nearby(Request $request): JsonResponse { return $this->enrich(parent::nearby($request),$request,true); }
    public function mine(Request $request): JsonResponse { return $this->enrich(parent::mine($request),$request,false); }

    public function show(Request $request, Property $property): JsonResponse
    {
        $viewer=$this->financialTokens->authenticate($request,false);
        $isOwner=$viewer && (int)$viewer->id===(int)$property->user_id;
        if(!$isOwner && $property->status==='published' && $this->finance->hasOverdueReceivable((int)$property->user_id)) abort(404);
        return $this->enrich(parent::show($request,$property),$request,false);
    }

    public function store(Request $request): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertFinancialListingAllowed($user);
        $this->prepareFinancialListingInput($request,null);
        $response=parent::store($request);
        $this->persistFinancialFieldsFromResponse($request,$response);
        return $this->enrich($response,$request,false);
    }

    public function update(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertFinancialListingAllowed($user);
        $this->prepareFinancialListingInput($request,$property);
        $response=parent::update($request,$property);
        $this->persistFinancialFieldsFromResponse($request,$response);
        return $this->enrich($response,$request,false);
    }

    public function submit(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */$user=$request->user();$this->assertFinancialListingAllowed($user);
        $this->assertFinancialListingComplete($property);
        return $this->enrich(parent::submit($request,$property),$request,false);
    }

    private function assertFinancialListingAllowed(User $user): void
    {
        if($this->finance->hasOpenReceivable((int)$user->id)) throw new ConflictHttpException('لديك مستحقات للمنصة. سدّد المستحقات الحالية قبل إنشاء أو إرسال إعلان جديد.');
    }

    private function prepareFinancialListingInput(Request $request, ?Property $existing): void
    {
        $purpose=(string)$request->input('purpose',$existing?->purpose??'');
        $hasRentFinance=$request->hasAny(['monthly_rent','rental_term_months','advance_months']);
        $rules=['price_display_mode'=>['nullable',Rule::in(['includes_sai','excludes_sai'])]];
        if($purpose==='rent' && $hasRentFinance){
            $rules += [
                'monthly_rent'=>['required','numeric','gt:0','max:9999999999999'],
                'rental_term_months'=>['required','integer','min:1','max:24'],
                'advance_months'=>['required','integer','min:1','max:24'],
            ];
        }
        $v=Validator::make($request->all(),$rules)->validate();
        if($purpose==='rent' && $hasRentFinance){
            $monthly=(float)($v['monthly_rent']??$existing?->monthly_rent??0);
            $term=(int)($v['rental_term_months']??$existing?->rental_term_months??0);
            $advance=(int)($v['advance_months']??$existing?->advance_months??0);
            if($advance>$term)throw ValidationException::withMessages(['advance_months'=>['عدد أشهر المقدم لا يمكن أن يتجاوز مدة التأجير.']]);
            $request->merge(['price'=>round($monthly*$advance,2)]);
        }
    }

    private function persistFinancialFieldsFromResponse(Request $request, JsonResponse $response): void
    {
        if($response->getStatusCode()>=400)return;
        $body=$response->getData(true);$id=(int)($body['data']['id']??0);if(!$id)return;
        $property=Property::query()->withoutGlobalScopes()->find($id);if(!$property)return;
        $purpose=(string)$property->purpose;
        $hasRentFinance=$request->hasAny(['monthly_rent','rental_term_months','advance_months'])
            || $property->monthly_rent!==null || $property->rental_term_months!==null || $property->advance_months!==null;
        if($purpose==='rent' && $hasRentFinance){
            $monthly=(float)$request->input('monthly_rent',$property->monthly_rent);
            $term=(int)$request->input('rental_term_months',$property->rental_term_months);
            $advance=(int)$request->input('advance_months',$property->advance_months);
            $property->forceFill(['monthly_rent'=>$monthly,'rental_term_months'=>$term,'advance_months'=>$advance,'price'=>round($monthly*$advance,2)]);
        }elseif($purpose!=='rent'){
            $property->forceFill(['monthly_rent'=>null,'rental_term_months'=>null,'advance_months'=>null]);
        }
        if($request->has('price_display_mode'))$property->price_display_mode=$request->input('price_display_mode');
        $property->saveQuietly();
    }

    private function assertFinancialListingComplete(Property $property): void
    {
        if($property->purpose==='rent'){
            if(!(float)$property->monthly_rent || !(int)$property->rental_term_months || !(int)$property->advance_months || (int)$property->rental_term_months>24 || (int)$property->advance_months>(int)$property->rental_term_months){
                throw new ConflictHttpException('أكمل إيجار الشهر ومدة التأجير وعدد أشهر المقدم قبل إرسال الإعلان.');
            }
        }
        $term=$property->currentSaiTerm()->first();
        if($term){
            $buyerPays=in_array($term->payer,['buyer','tenant'],true);
            if($buyerPays && !in_array($property->price_display_mode,['includes_sai','excludes_sai'],true)){
                $property->forceFill(['price_display_mode'=>'excludes_sai'])->saveQuietly();
            }
            if(!$buyerPays && $property->price_display_mode!==null)$property->forceFill(['price_display_mode'=>null])->saveQuietly();
        }
    }

    private function enrich(JsonResponse $response, Request $request, bool $hideOverduePublicRows): JsonResponse
    {
        if($response->getStatusCode()>=400)return $response;
        $body=$response->getData(true);if(!isset($body['data']))return $response;
        if(array_is_list($body['data']))$body['data']=$this->enrichRows($body['data'],$hideOverduePublicRows);
        elseif(is_array($body['data'])&&isset($body['data']['id']))$body['data']=$this->enrichRow($body['data']);
        $response->setData($body);return $response;
    }

    private function enrichRows(array $rows, bool $hideOverduePublicRows): array
    {
        if($rows===[])return [];
        if($hideOverduePublicRows){
            $propertyIds=array_values(array_filter(array_map(fn(array $row)=>(int)($row['id']??0),$rows)));
            $owners=Property::query()->withoutGlobalScopes()->whereIn('id',$propertyIds)->pluck('user_id','id');
            $ownerIds=$owners->values()->map(fn($id)=>(int)$id)->unique()->values()->all();
            $overdue=DB::table('property_platform_receivables')
                ->whereIn('advertiser_user_id',$ownerIds)
                ->whereIn('status',['open','under_review','overdue','disputed'])
                ->whereColumn('amount_paid','<','amount_total')
                ->where('due_at','<=',now())
                ->pluck('advertiser_user_id')->map(fn($id)=>(int)$id)->unique()->flip();
            $rows=array_values(array_filter($rows,function(array $row)use($owners,$overdue):bool{
                $propertyId=(int)($row['id']??0);$ownerId=(int)($owners[$propertyId]??0);
                return $ownerId===0||!$overdue->has($ownerId);
            }));
        }
        return array_map(fn(array $row)=>$this->enrichRow($row),$rows);
    }

    private function enrichRow(array $row): array
    {
        $id=(int)($row['id']??0);if(!$id)return $row;
        $property=Property::query()->withoutGlobalScopes()->find($id);if(!$property)return $row;
        $term=$property->current_sai_term_id?DB::table('property_sai_terms')->where('id',$property->current_sai_term_id)->first():null;
        $saiAmount=0.0;$sai=null;$note=null;$displayPrice=(float)$property->price;
        if($term){
            $basis=$property->purpose==='rent'?(float)($property->monthly_rent?:0):(float)$property->price;
            if($basis>0)$saiAmount=round($basis*((float)$term->sai_rate_percent/100),2);
            $buyerPays=in_array($term->payer,['buyer','tenant'],true);
            $displayMode=$property->price_display_mode ?: ($buyerPays?'excludes_sai':null);
            if($buyerPays){
                if($displayMode==='includes_sai'){$displayPrice=round((float)$property->price+$saiAmount,2);$note='المبلغ شامل السعي';}
                else $note='المبلغ غير شامل السعي';
            }
            $sai=['rate_percent'=>(float)$term->sai_rate_percent,'payer'=>$term->payer,'amount'=>$saiAmount];
        }
        return array_merge($row,[
            'base_price'=>(float)$property->price,'display_price'=>$displayPrice,'price_display_mode'=>$property->price_display_mode ?: (($term&&in_array($term->payer,['buyer','tenant'],true))?'excludes_sai':null),
            'price_display_note'=>$note,'monthly_rent'=>$property->monthly_rent!==null?(float)$property->monthly_rent:null,
            'rental_term_months'=>$property->rental_term_months,'advance_months'=>$property->advance_months,'sai'=>$sai,
            'financial_hold'=>$this->finance->hasOverdueReceivable((int)$property->user_id),
            'sai_attestation_required'=>$this->finance->pendingSaiAttestation($property),
        ]);
    }
}
