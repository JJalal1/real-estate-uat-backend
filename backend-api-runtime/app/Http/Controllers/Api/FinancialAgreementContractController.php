<?php

namespace App\Http\Controllers\Api;

use App\Models\MessageThread;
use App\Models\Property;
use App\Models\PropertyAgreement;
use App\Models\RentalContract;
use App\Services\AuditLogService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class FinancialAgreementContractController extends AgreementContractController
{
    public function __construct(AuditLogService $audit, UserNotificationService $notifications)
    {
        parent::__construct($audit,$notifications);
    }

    public function startAgreement(Request $request, MessageThread $thread): JsonResponse
    {
        $property=Property::query()->withoutGlobalScopes()->findOrFail($thread->property_id);
        $rent=$this->prepareRentAgreementRequest($request,$property,null);
        $response=parent::startAgreement($request,$thread);
        $this->persistAgreementRentFields($response,$rent);
        return $response;
    }

    public function reviseAgreement(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        $property=Property::query()->withoutGlobalScopes()->findOrFail($agreement->property_id);
        $current=DB::table('property_agreement_revisions')->where('property_agreement_id',$agreement->id)->orderByDesc('revision_number')->first();
        $rent=$this->prepareRentAgreementRequest($request,$property,$current);
        $response=parent::reviseAgreement($request,$agreement);
        $this->persistAgreementRentFields($response,$rent);
        return $response;
    }

    public function startRentalContract(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        $response=parent::startRentalContract($request,$agreement);
        $body=$response->getData(true);$contractId=(int)($body['data']['id']??0);
        if($contractId){
            $agreementRevision=DB::table('property_agreement_revisions')->where('property_agreement_id',$agreement->id)->orderByDesc('revision_number')->first();
            if($agreementRevision && ($agreementRevision->monthly_rent!==null || $agreementRevision->rental_term_months!==null || $agreementRevision->advance_months!==null)){
                DB::table('rental_contract_revisions')->where('rental_contract_id',$contractId)->orderByDesc('revision_number')->limit(1)->update([
                    'monthly_rent'=>$agreementRevision->monthly_rent,'rental_term_months'=>$agreementRevision->rental_term_months,
                    'advance_months'=>$agreementRevision->advance_months,
                ]);
            }
        }
        return $response;
    }

    public function reviseRentalContract(Request $request, RentalContract $contract): JsonResponse
    {
        $current=DB::table('rental_contract_revisions')->where('rental_contract_id',$contract->id)->orderByDesc('revision_number')->first();
        $hasFinancialFields=$request->hasAny(['monthly_rent','rental_term_months','advance_months'])
            || $current?->monthly_rent!==null || $current?->rental_term_months!==null || $current?->advance_months!==null;
        $monthly=$request->input('monthly_rent',$current?->monthly_rent);
        $term=$request->input('rental_term_months',$current?->rental_term_months);
        $advance=$request->input('advance_months',$current?->advance_months);
        if($hasFinancialFields){
            $v=Validator::make(['monthly_rent'=>$monthly,'rental_term_months'=>$term,'advance_months'=>$advance],[
                'monthly_rent'=>['required','numeric','gt:0'],'rental_term_months'=>['required','integer','between:1,24'],'advance_months'=>['required','integer','between:1,24'],
            ])->validate();
            if((int)$v['advance_months']>(int)$v['rental_term_months'])abort(422,'عدد أشهر المقدم لا يمكن أن يتجاوز مدة التأجير.');
            $request->merge(['rent_amount'=>round((float)$v['monthly_rent']*(int)$v['advance_months'],2),'rent_cadence'=>'monthly']);
            $monthly=(float)$v['monthly_rent'];$term=(int)$v['rental_term_months'];$advance=(int)$v['advance_months'];
        }
        $response=parent::reviseRentalContract($request,$contract);
        if($hasFinancialFields){
            DB::table('rental_contract_revisions')->where('rental_contract_id',$contract->id)->orderByDesc('revision_number')->limit(1)->update([
                'monthly_rent'=>$monthly,'rental_term_months'=>$term,'advance_months'=>$advance,
            ]);
        }
        return $response;
    }

    private function prepareRentAgreementRequest(Request $request, Property $property, ?object $current): ?array
    {
        if($property->purpose!=='rent')return null;
        $hasFinancialFields=$request->hasAny(['monthly_rent','rental_term_months','advance_months'])
            || $current?->monthly_rent!==null || $current?->rental_term_months!==null || $current?->advance_months!==null
            || $property->monthly_rent!==null || $property->rental_term_months!==null || $property->advance_months!==null;
        if(!$hasFinancialFields)return null;

        $monthly=$request->input('monthly_rent',$current?->monthly_rent??$property->monthly_rent);
        $term=$request->input('rental_term_months',$current?->rental_term_months??$property->rental_term_months);
        $advance=$request->input('advance_months',$current?->advance_months??$property->advance_months);
        $v=Validator::make(['monthly_rent'=>$monthly,'rental_term_months'=>$term,'advance_months'=>$advance],[
            'monthly_rent'=>['required','numeric','gt:0'],'rental_term_months'=>['required','integer','between:1,24'],'advance_months'=>['required','integer','between:1,24'],
        ])->validate();
        if((int)$v['advance_months']>(int)$v['rental_term_months'])abort(422,'عدد أشهر المقدم لا يمكن أن يتجاوز مدة التأجير.');
        $request->merge(['agreed_amount'=>round((float)$v['monthly_rent']*(int)$v['advance_months'],2),'rent_cadence'=>'monthly']);
        return ['monthly_rent'=>(float)$v['monthly_rent'],'rental_term_months'=>(int)$v['rental_term_months'],'advance_months'=>(int)$v['advance_months']];
    }

    private function persistAgreementRentFields(JsonResponse $response, ?array $rent): void
    {
        if(!$rent||$response->getStatusCode()>=400)return;
        $body=$response->getData(true);$agreementId=(int)($body['data']['id']??0);if(!$agreementId)return;
        DB::table('property_agreement_revisions')->where('property_agreement_id',$agreementId)->orderByDesc('revision_number')->limit(1)->update($rent);
    }
}
