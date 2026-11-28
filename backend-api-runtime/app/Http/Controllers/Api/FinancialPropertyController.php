<?php

namespace App\Http\Controllers\Api;

use App\Models\Property;
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

    public function index(Request $request): JsonResponse { return $this->enrich(parent::index($request)); }
    public function nearby(Request $request): JsonResponse { return $this->enrich(parent::nearby($request)); }
    public function marketplace(Request $request): JsonResponse
    {
        $response = parent::marketplace($request);
        $body = $response->getData(true);
        $unique = [];
        foreach ($body['data']['sections'] as $rows) foreach ($rows as $row) $unique[$row['id']] = $row;
        $enriched = $this->enrichRows(array_values($unique));
        $byId = array_column($enriched, null, 'id');
        foreach ($body['data']['sections'] as $key => $rows) {
            $body['data']['sections'][$key] = array_values(array_filter(array_map(fn ($row) => $byId[$row['id']] ?? null, $rows)));
        }
        $response->setData($body);
        return $response;
    }
    public function mine(Request $request): JsonResponse { return $this->enrich(parent::mine($request)); }

    public function show(Request $request, Property $property): JsonResponse
    {
        return $this->enrich(parent::show($request,$property));
    }

    public function store(Request $request): JsonResponse
    {
        return $this->enrich(parent::store($request));
    }

    public function update(Request $request, Property $property): JsonResponse
    {
        return $this->enrich(parent::update($request, $property));
    }

    public function submit(Request $request, Property $property): JsonResponse
    {
        $this->assertFinancialListingComplete($property);
        return $this->enrich(parent::submit($request,$property));
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

    private function enrich(JsonResponse $response): JsonResponse
    {
        if($response->getStatusCode()>=400)return $response;
        $body=$response->getData(true);if(!isset($body['data']))return $response;
        if(array_is_list($body['data']))$body['data']=$this->enrichRows($body['data']);
        elseif(is_array($body['data'])&&isset($body['data']['id']))$body['data']=$this->enrichRows([$body['data']])[0];
        $response->setData($body);return $response;
    }

    private function enrichRows(array $rows): array
    {
        if ($rows === []) return [];
        // One request-local snapshot for the bounded page. No cross-user or
        // cross-request cache of financial state, terms or authorization.
        $ids = array_values(array_filter(array_map(fn (array $row) => (int) ($row['id'] ?? 0), $rows)));
        $properties = Property::query()->withoutGlobalScopes()->whereIn('id', $ids)->get()->keyBy('id');
        $terms = DB::table('property_sai_terms')->whereIn('id', $properties->pluck('current_sai_term_id')->filter()->unique())
            ->get()->keyBy('id');
        $attested = DB::table('property_sai_attestations')->whereIn('property_id', $ids)
            ->get(['property_id', 'sai_term_id'])->mapWithKeys(fn ($row) => [$row->property_id.':'.$row->sai_term_id => true]);
        return array_map(function (array $row) use ($properties, $terms, $attested): array {
            $property = $properties->get((int) ($row['id'] ?? 0));
            if (! $property) return $row;
            $term = $terms->get($property->current_sai_term_id);
            $pending = $property->status === 'published' && $property->current_sai_term_id
                && ! $attested->has($property->id.':'.$property->current_sai_term_id);
            return $this->enrichLoadedRow($row, $property, $term, (bool) $pending);
        }, $rows);
    }

    private function enrichLoadedRow(array $row, Property $property, ?object $term, bool $pending): array
    {
        return array_merge($row, $this->publicPriceData($property, $term), [
            'financial_hold'=>false,
            'sai_attestation_required'=>$pending,
            'sai_attestation_text'=>(int)(request()->user()?->id ?? 0) === (int)$property->user_id ? ($term ? $this->finance->attestationText($property, $term) : PropertyFinancialService::SAI_ATTESTATION_TEXT) : null,
        ]);
    }
}
