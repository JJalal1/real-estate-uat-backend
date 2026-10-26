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
use App\Services\PropertyIdentityService;
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
        PropertyIdentityService $identity,
        ListingWorkflowService $workflow,
        private readonly PropertyFinancialService $finance,
    ) {
        parent::__construct($financialTokens,$audit,$storage,$regions,$assets,$identity,$workflow);
    }

    public function index(Request $request): JsonResponse { return $this->enrich(parent::index($request),$request,true); }
    public function nearby(Request $request): JsonResponse { return $this->enrich(parent::nearby($request),$request,true); }
    public function marketplace(Request $request): JsonResponse
    {
        $response = parent::marketplace($request);
        $body = $response->getData(true);
        $unique = [];
        foreach ($body['data']['sections'] as $rows) foreach ($rows as $row) $unique[$row['id']] = $row;
        $enriched = $this->enrichRows(array_values($unique), true);
        $byId = array_column($enriched, null, 'id');
        foreach ($body['data']['sections'] as $key => $rows) {
            $body['data']['sections'][$key] = array_values(array_filter(array_map(fn ($row) => $byId[$row['id']] ?? null, $rows)));
        }
        $response->setData($body);
        return $response;
    }
    public function mine(Request $request): JsonResponse { return $this->enrich(parent::mine($request),$request,false); }

    public function show(Request $request, Property $property): JsonResponse
    {
        $viewer=$this->financialTokens->authenticate($request,false);
        $isOwner=$viewer && (int)$viewer->id===(int)$property->user_id;
        if (!$isOwner && !$property->isPubliclyAvailable()) abort(404);
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
        if ((int) $request->input('listing_input_version', $existing?->listing_input_version ?? 1) >= 6) {
            $purpose = (string) $request->input('purpose', $existing?->purpose ?? '');
            if ($purpose === 'rent') {
                $v = Validator::make(['monthly_rent' => $request->input('monthly_rent', $existing?->monthly_rent)], ['monthly_rent' => ['required', 'numeric', 'gt:0', 'max:9999999999999']])->validate();
                $request->merge(['monthly_rent' => $v['monthly_rent'], 'price' => round((float) $v['monthly_rent'], 2)]);
            }
            $request->merge(['price_display_mode' => 'excludes_sai']);
            return;
        }
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
        if ((int) $property->listing_input_version >= 6) {
            $rent = $property->purpose === 'rent';
            $conditions = collect($property->rental_conditions ?? []);
            $monthly = $rent ? (float) $request->input('monthly_rent', $property->monthly_rent) : null;
            $property->forceFill(['monthly_rent' => $monthly,
                'rental_term_months' => $rent ? ($conditions->firstWhere('kind', 'duration')['months'] ?? null) : null,
                'advance_months' => $rent ? ($conditions->firstWhere('kind', 'advance')['months'] ?? null) : null,
                'price_display_mode' => 'excludes_sai']);
            if ($rent) $property->price = round($monthly, 2);
            $property->saveQuietly();
            return;
        }
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
        if ((int) $property->listing_input_version >= 6) {
            if ($property->purpose === 'rent' && (float) $property->monthly_rent <= 0) throw new ConflictHttpException('أكمل الإيجار الشهري قبل إرسال الإعلان.');
            $property->forceFill(['price_display_mode' => 'excludes_sai'])->saveQuietly();
            return;
        }
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
        elseif(is_array($body['data'])&&isset($body['data']['id']))$body['data']=$this->enrichRows([$body['data']], false)[0];
        $response->setData($body);return $response;
    }

    private function enrichRows(array $rows, bool $hideOverduePublicRows): array
    {
        if ($rows === []) return [];
        // One request-local snapshot for the bounded page. No cross-user or
        // cross-request cache of financial state, terms or authorization.
        $ids = array_values(array_filter(array_map(fn (array $row) => (int) ($row['id'] ?? 0), $rows)));
        $properties = Property::query()->withoutGlobalScopes()->whereIn('id', $ids)->get()->keyBy('id');
        if ($hideOverduePublicRows) {
            $overdue = DB::table('property_platform_receivables')
                ->whereIn('advertiser_user_id', $properties->pluck('user_id')->unique())
                ->whereIn('status', ['open','under_review','overdue','disputed'])
                ->whereColumn('amount_paid', '<', 'amount_total')->where('due_at', '<=', now())
                ->pluck('advertiser_user_id')->map(fn ($id) => (int) $id)->flip();
            $rows = array_values(array_filter($rows, function (array $row) use ($properties, $overdue): bool {
                $owner = (int) ($properties->get((int) ($row['id'] ?? 0))?->user_id ?? 0);
                return $owner === 0 || ! $overdue->has($owner);
            }));
        }
        $terms = DB::table('property_sai_terms')->whereIn('id', $properties->pluck('current_sai_term_id')->filter()->unique())
            ->get()->keyBy('id');
        $attested = DB::table('property_sai_attestations')->whereIn('property_id', $ids)
            ->get(['property_id', 'sai_term_id'])->mapWithKeys(fn ($row) => [$row->property_id.':'.$row->sai_term_id => true]);
        $holds = [];
        return array_map(function (array $row) use ($properties, $terms, $attested, &$holds): array {
            $property = $properties->get((int) ($row['id'] ?? 0));
            if (! $property) return $row;
            $owner = (int) $property->user_id;
            // Preserve the authoritative service's overdue-hold side effects,
            // once per owner in this page rather than once per listing.
            if (! array_key_exists($owner, $holds)) $holds[$owner] = $this->finance->hasOverdueReceivable($owner);
            $term = $terms->get($property->current_sai_term_id);
            $pending = $property->status === 'published' && $property->current_sai_term_id
                && ! $attested->has($property->id.':'.$property->current_sai_term_id);
            return $this->enrichLoadedRow($row, $property, $term, (bool) $pending, $holds[$owner]);
        }, $rows);
    }

    private function enrichLoadedRow(array $row, Property $property, ?object $term, bool $pending, bool $overdue): array
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
        return array_merge($row,[
            'base_price'=>(float)$property->price,'display_price'=>$displayPrice,'price_display_mode'=>$property->price_display_mode ?: (($term&&in_array($term->payer,['buyer','tenant'],true))?'excludes_sai':null),
            'price_display_note'=>$note,'monthly_rent'=>$property->monthly_rent!==null?(float)$property->monthly_rent:null,
            'rental_term_months'=>$property->rental_term_months,'advance_months'=>$property->advance_months,'sai'=>$sai,
            'financial_hold'=>$overdue,
            'sai_attestation_required'=>$pending,
            'sai_attestation_text'=>(int)(request()->user()?->id ?? 0) === (int)$property->user_id ? ($term ? $this->finance->attestationText($property, $term) : PropertyFinancialService::SAI_ATTESTATION_TEXT) : null,
        ]);
    }
}
