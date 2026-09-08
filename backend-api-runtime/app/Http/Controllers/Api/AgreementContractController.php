<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MessageThread;
use App\Models\MessageThreadParticipant;
use App\Models\Property;
use App\Models\PropertyAgreement;
use App\Models\RentalContract;
use App\Models\User;
use App\Models\ViewingBooking;
use App\Services\AuditLogService;
use App\Services\UserNotificationService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class AgreementContractController extends Controller
{
    private const CADENCES = ['monthly','quarterly','semiannual','annual'];

    public function __construct(
        private readonly AuditLogService $audit,
        private readonly UserNotificationService $notifications,
    ) {}

    public function agreementsMine(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=PropertyAgreement::query()
            ->where(fn(Builder $q)=>$q->where('requester_user_id',$user->id)->orWhere('advertiser_user_id',$user->id))
            ->latest('id')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(PropertyAgreement $a)=>$this->agreementData($a,$user,false))->values()]);
    }

    public function agreementShow(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$this->assertAgreementParty($user,$agreement);
        return response()->json(['data'=>$this->agreementData($agreement,$user,true)]);
    }

    public function startAgreement(Request $request, MessageThread $thread): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $this->assertThreadParty($actor,$thread);
        $property=Property::query()->findOrFail($thread->property_id);abort_unless($property->status==='published',409,'A new agreement can only start from a published property.');
        [$requesterId,$advertiserId]=$this->canonicalParties($thread,$property);
        $current=$this->latestAgreementForThread($thread->id);
        if($current&&in_array($current->status,['draft','accepted'],true)) return response()->json(['message'=>'Agreement already exists for this property conversation.','data'=>$this->agreementData($current,$actor,true)]);
        $terms=$this->agreementTerms($request,$property->purpose,null);
        $viewingId=$request->integer('viewing_booking_id') ?: null;
        if($viewingId)$this->assertViewingLink($viewingId,$thread->id,$requesterId);

        $agreement=DB::transaction(function()use($actor,$thread,$property,$requesterId,$advertiserId,$terms,$viewingId,$request): PropertyAgreement{
            $this->lockKey(5101,(int)$thread->id);
            $existing=$this->latestAgreementForThread($thread->id,true);
            if($existing&&in_array($existing->status,['draft','accepted'],true)) return $existing;
            $linkedViewing=$viewingId ?: ViewingBooking::query()->where('message_thread_id',$thread->id)->where('requester_user_id',$requesterId)->where('status','completed')->latest('completed_at')->value('id');
            $agreement=PropertyAgreement::query()->create([
                'reference'=>$this->reference('AGR'),'property_id'=>$property->id,'message_thread_id'=>$thread->id,'viewing_booking_id'=>$linkedViewing,
                'requester_user_id'=>$requesterId,'advertiser_user_id'=>$advertiserId,'transaction_type'=>$property->purpose,'status'=>'draft','created_by_user_id'=>$actor->id,
            ]);
            $this->insertAgreementRevision($agreement,1,$terms,$actor);
            $this->audit->record($actor,'agreement.created',$agreement,['property_id'=>$property->id,'message_thread_id'=>$thread->id,'transaction_type'=>$property->purpose,'revision_number'=>1],$request,$this->otherAgreementPartyId($agreement,$actor));
            return $agreement;
        });
        $this->notifyAgreementOther($agreement,$actor,'agreement_created','اتفاق جديد للمراجعة','تم إنشاء مسودة اتفاق مرتبطة بالعقار. راجع الشروط قبل القبول.');
        return response()->json(['message'=>'Agreement created.','data'=>$this->agreementData($agreement->fresh(),$actor,true)],201);
    }

    public function reviseAgreement(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();$this->assertAgreementParty($actor,$agreement);
        $result=DB::transaction(function()use($request,$agreement,$actor): PropertyAgreement{
            $a=PropertyAgreement::query()->whereKey($agreement->id)->lockForUpdate()->firstOrFail();$this->assertAgreementParty($actor,$a);abort_unless($a->status==='draft',409,'Accepted or cancelled agreements cannot be revised.');
            $current=$this->agreementRevision($a->id,true);$terms=$this->agreementTerms($request,$a->transaction_type,$current);$next=((int)$current->revision_number)+1;
            $this->insertAgreementRevision($a,$next,$terms,$actor);
            $this->audit->record($actor,'agreement.revised',$a,['revision_number'=>$next],$request,$this->otherAgreementPartyId($a,$actor));
            return $a;
        });
        $this->notifyAgreementOther($result,$actor,'agreement_revised','تم تحديث شروط الاتفاق','تم إنشاء نسخة جديدة من شروط الاتفاق وتحتاج إلى مراجعة وقبول جديد من الطرفين.');
        return response()->json(['message'=>'Agreement revision created. Previous revision acceptances do not carry forward.','data'=>$this->agreementData($result->fresh(),$actor,true)]);
    }

    public function acceptAgreement(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        $validated=$request->validate(['revision_id'=>['required','integer','min:1']]);/** @var User $actor */ $actor=$request->user();$this->assertAgreementParty($actor,$agreement);
        $becameAccepted=false;
        $result=DB::transaction(function()use($request,$agreement,$actor,$validated,&$becameAccepted): PropertyAgreement{
            $a=PropertyAgreement::query()->whereKey($agreement->id)->lockForUpdate()->firstOrFail();$this->assertAgreementParty($actor,$a);abort_unless(in_array($a->status,['draft','accepted'],true),409,'This agreement cannot be accepted.');
            $revision=$this->agreementRevision($a->id,true);abort_unless((int)$revision->id===(int)$validated['revision_id'],409,'Agreement terms changed. Review the latest revision before accepting.');
            $existing=DB::table('property_agreement_acceptances')->where('property_agreement_revision_id',$revision->id)->where('user_id',$actor->id)->exists();
            if(!$existing){DB::table('property_agreement_acceptances')->insert(['property_agreement_revision_id'=>$revision->id,'user_id'=>$actor->id,'party_role'=>$this->agreementRole($a,$actor),'accepted_at'=>now()]);$this->audit->record($actor,'agreement.revision_accepted',$a,['revision_number'=>(int)$revision->revision_number],$request,$this->otherAgreementPartyId($a,$actor));}
            $acceptedIds=DB::table('property_agreement_acceptances')->where('property_agreement_revision_id',$revision->id)->whereIn('user_id',[$a->requester_user_id,$a->advertiser_user_id])->pluck('user_id')->map(fn($id)=>(int)$id)->unique();
            if($acceptedIds->contains((int)$a->requester_user_id)&&$acceptedIds->contains((int)$a->advertiser_user_id)&&$a->status!=='accepted'){$a->forceFill(['status'=>'accepted','accepted_at'=>now()])->save();$becameAccepted=true;$this->audit->record($actor,'agreement.accepted',$a,['revision_number'=>(int)$revision->revision_number],$request);}
            return $a;
        });
        if($becameAccepted)$this->notifyAgreementOther($result,$actor,'agreement_accepted','تم اعتماد الاتفاق داخل التطبيق','وافق الطرفان على نفس نسخة الاتفاق.');
        else $this->notifyAgreementOther($result,$actor,'agreement_party_accepted','تم تسجيل قبول أحد الطرفين','راجع النسخة الحالية من الاتفاق إذا لم تكن قد قبلتها بعد.');
        return response()->json(['message'=>$becameAccepted?'Agreement accepted by both parties.':'Agreement revision acceptance recorded.','data'=>$this->agreementData($result->fresh(),$actor,true)]);
    }

    public function cancelAgreement(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        $validated=$request->validate(['reason'=>['required','string','min:2','max:2000']]);/** @var User $actor */ $actor=$request->user();$this->assertAgreementParty($actor,$agreement);
        $result=DB::transaction(function()use($request,$agreement,$actor,$validated): PropertyAgreement{$a=PropertyAgreement::query()->whereKey($agreement->id)->lockForUpdate()->firstOrFail();$this->assertAgreementParty($actor,$a);abort_unless($a->status==='draft',409,'Only a draft agreement can be cancelled.');$a->forceFill(['status'=>'cancelled','cancelled_at'=>now(),'cancellation_reason'=>$validated['reason']])->save();$this->audit->record($actor,'agreement.cancelled',$a,[],$request,$this->otherAgreementPartyId($a,$actor));return $a;});
        $this->notifyAgreementOther($result,$actor,'agreement_cancelled','تم إلغاء مسودة الاتفاق','تم إلغاء مسودة الاتفاق داخل التطبيق.');
        return response()->json(['message'=>'Agreement cancelled.','data'=>$this->agreementData($result->fresh(),$actor,true)]);
    }

    public function contractsMine(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$rows=RentalContract::query()->where(fn(Builder $q)=>$q->where('tenant_user_id',$user->id)->orWhere('advertiser_user_id',$user->id))->latest('id')->limit(250)->get();
        return response()->json(['data'=>$rows->map(fn(RentalContract $c)=>$this->contractData($c,$user,false))->values()]);
    }

    public function contractShow(Request $request, RentalContract $contract): JsonResponse
    {
        /** @var User $user */ $user=$request->user();$this->assertContractParty($user,$contract);return response()->json(['data'=>$this->contractData($contract,$user,true)]);
    }

    public function startRentalContract(Request $request, PropertyAgreement $agreement): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();$this->assertAgreementParty($actor,$agreement);abort_unless($agreement->status==='accepted',409,'The agreement must be accepted by both parties first.');abort_unless($agreement->transaction_type==='rent',409,'Rental contracts are only available for rental agreements.');
        $existing=RentalContract::query()->where('property_agreement_id',$agreement->id)->first();if($existing)return response()->json(['message'=>'Rental contract already exists for this agreement.','data'=>$this->contractData($existing,$actor,true)]);
        $agreementRevision=$this->agreementRevision($agreement->id);$terms=$this->contractTerms($request,null,$agreementRevision);$property=Property::query()->findOrFail($agreement->property_id);$tenant=User::query()->findOrFail($agreement->requester_user_id);$advertiser=User::query()->findOrFail($agreement->advertiser_user_id);
        $contract=DB::transaction(function()use($request,$agreement,$actor,$terms,$property,$tenant,$advertiser): RentalContract{
            $a=PropertyAgreement::query()->whereKey($agreement->id)->lockForUpdate()->firstOrFail();abort_unless($a->status==='accepted'&&$a->transaction_type==='rent',409,'Agreement is no longer eligible for a rental contract.');
            $this->lockKey(5102,(int)$a->id);$existing=RentalContract::query()->where('property_agreement_id',$a->id)->lockForUpdate()->first();if($existing)return $existing;
            $contract=RentalContract::query()->create(['reference'=>$this->reference('RNT'),'property_agreement_id'=>$a->id,'property_id'=>$a->property_id,'message_thread_id'=>$a->message_thread_id,'tenant_user_id'=>$a->requester_user_id,'advertiser_user_id'=>$a->advertiser_user_id,'property_title_snapshot'=>$property->title,'property_address_snapshot'=>$property->address,'tenant_name_snapshot'=>$tenant->name,'advertiser_name_snapshot'=>$advertiser->name,'status'=>'draft','created_by_user_id'=>$actor->id]);
            $this->insertContractRevision($contract,1,$terms,$actor);$this->audit->record($actor,'rental_contract.created',$contract,['agreement_id'=>$a->id,'revision_number'=>1],$request,$this->otherContractPartyId($contract,$actor));return $contract;
        });
        $this->notifyContractOther($contract,$actor,'rental_contract_created','مسودة عقد إيجار للمراجعة','تم إنشاء سجل عقد إيجار داخل التطبيق. راجع البنود قبل القبول.');
        return response()->json(['message'=>'In-app rental contract created.','data'=>$this->contractData($contract->fresh(),$actor,true)],201);
    }

    public function reviseRentalContract(Request $request, RentalContract $contract): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();$this->assertContractParty($actor,$contract);
        $result=DB::transaction(function()use($request,$contract,$actor): RentalContract{$c=RentalContract::query()->whereKey($contract->id)->lockForUpdate()->firstOrFail();$this->assertContractParty($actor,$c);abort_unless($c->status==='draft',409,'Active, cancelled or terminated contract records cannot be revised.');$current=$this->contractRevision($c->id,true);$terms=$this->contractTerms($request,$current,null);$next=((int)$current->revision_number)+1;$this->insertContractRevision($c,$next,$terms,$actor);$this->audit->record($actor,'rental_contract.revised',$c,['revision_number'=>$next],$request,$this->otherContractPartyId($c,$actor));return $c;});
        $this->notifyContractOther($result,$actor,'rental_contract_revised','تم تحديث بنود عقد الإيجار','تم إنشاء نسخة جديدة من بنود العقد وتحتاج إلى قبول جديد من الطرفين.');
        return response()->json(['message'=>'Rental contract revision created.','data'=>$this->contractData($result->fresh(),$actor,true)]);
    }

    public function acceptRentalContract(Request $request, RentalContract $contract): JsonResponse
    {
        $validated=$request->validate(['revision_id'=>['required','integer','min:1']]);/** @var User $actor */ $actor=$request->user();$this->assertContractParty($actor,$contract);$becameActive=false;
        $result=DB::transaction(function()use($request,$contract,$actor,$validated,&$becameActive): RentalContract{$c=RentalContract::query()->whereKey($contract->id)->lockForUpdate()->firstOrFail();$this->assertContractParty($actor,$c);abort_unless(in_array($c->status,['draft','active'],true),409,'This contract record cannot be accepted.');$revision=$this->contractRevision($c->id,true);abort_unless((int)$revision->id===(int)$validated['revision_id'],409,'Contract terms changed. Review the latest revision before accepting.');$exists=DB::table('rental_contract_acceptances')->where('rental_contract_revision_id',$revision->id)->where('user_id',$actor->id)->exists();if(!$exists){DB::table('rental_contract_acceptances')->insert(['rental_contract_revision_id'=>$revision->id,'user_id'=>$actor->id,'party_role'=>$this->contractRole($c,$actor),'accepted_at'=>now()]);$this->audit->record($actor,'rental_contract.revision_accepted',$c,['revision_number'=>(int)$revision->revision_number],$request,$this->otherContractPartyId($c,$actor));}$ids=DB::table('rental_contract_acceptances')->where('rental_contract_revision_id',$revision->id)->whereIn('user_id',[$c->tenant_user_id,$c->advertiser_user_id])->pluck('user_id')->map(fn($id)=>(int)$id)->unique();if($ids->contains((int)$c->tenant_user_id)&&$ids->contains((int)$c->advertiser_user_id)&&$c->status!=='active'){$c->forceFill(['status'=>'active','activated_at'=>now()])->save();$becameActive=true;$this->audit->record($actor,'rental_contract.activated',$c,['revision_number'=>(int)$revision->revision_number,'in_app_only'=>true],$request);}return $c;});
        if($becameActive)$this->notifyContractOther($result,$actor,'rental_contract_active','تم قبول عقد الإيجار داخل التطبيق','وافق الطرفان على نفس نسخة سجل عقد الإيجار داخل التطبيق.');else $this->notifyContractOther($result,$actor,'rental_contract_party_accepted','تم تسجيل قبول أحد الطرفين','راجع النسخة الحالية من عقد الإيجار إذا لم تكن قد قبلتها بعد.');
        return response()->json(['message'=>$becameActive?'In-app rental contract accepted by both parties.':'Rental contract revision acceptance recorded.','data'=>$this->contractData($result->fresh(),$actor,true)]);
    }

    public function cancelRentalContract(Request $request, RentalContract $contract): JsonResponse
    {
        $validated=$request->validate(['reason'=>['required','string','min:2','max:2000']]);/** @var User $actor */ $actor=$request->user();$this->assertContractParty($actor,$contract);$result=DB::transaction(function()use($request,$contract,$actor,$validated): RentalContract{$c=RentalContract::query()->whereKey($contract->id)->lockForUpdate()->firstOrFail();$this->assertContractParty($actor,$c);abort_unless($c->status==='draft',409,'Only a draft contract record can be cancelled.');$c->forceFill(['status'=>'cancelled','cancelled_at'=>now(),'closure_reason'=>$validated['reason']])->save();$this->audit->record($actor,'rental_contract.cancelled',$c,['in_app_only'=>true],$request,$this->otherContractPartyId($c,$actor));return $c;});$this->notifyContractOther($result,$actor,'rental_contract_cancelled','تم إلغاء مسودة عقد الإيجار','تم إلغاء مسودة سجل عقد الإيجار داخل التطبيق.');return response()->json(['message'=>'Rental contract draft cancelled.','data'=>$this->contractData($result->fresh(),$actor,true)]);
    }

    public function terminateRentalContract(Request $request, RentalContract $contract): JsonResponse
    {
        $validated=$request->validate(['reason'=>['required','string','min:2','max:3000']]);/** @var User $actor */ $actor=$request->user();$this->assertContractParty($actor,$contract);$result=DB::transaction(function()use($request,$contract,$actor,$validated): RentalContract{$c=RentalContract::query()->whereKey($contract->id)->lockForUpdate()->firstOrFail();$this->assertContractParty($actor,$c);abort_unless($c->status==='active',409,'Only an active in-app contract record can be marked terminated.');$c->forceFill(['status'=>'terminated','terminated_at'=>now(),'closure_reason'=>$validated['reason']])->save();$this->audit->record($actor,'rental_contract.terminated',$c,['in_app_only'=>true,'legal_effect_not_asserted'=>true],$request,$this->otherContractPartyId($c,$actor));return $c;});$this->notifyContractOther($result,$actor,'rental_contract_terminated','تم تسجيل إنهاء عقد الإيجار داخل التطبيق','تم تسجيل إنهاء سجل عقد الإيجار داخل التطبيق. لا يمثل ذلك بحد ذاته توثيقاً أو حكماً قانونياً.');return response()->json(['message'=>'In-app rental contract record marked terminated. No legal or governmental effect is asserted.','data'=>$this->contractData($result->fresh(),$actor,true)]);
    }

    private function agreementTerms(Request $request,string $type,?object $current): array
    {
        $base=$current?['agreed_amount'=>$current->agreed_amount,'currency'=>$current->currency,'rent_cadence'=>$current->rent_cadence,'security_deposit_amount'=>$current->security_deposit_amount,'rental_start_date'=>$current->rental_start_date,'rental_end_date'=>$current->rental_end_date,'conditions'=>$current->conditions]:[];$input=array_merge($base,$request->only(['agreed_amount','currency','rent_cadence','security_deposit_amount','rental_start_date','rental_end_date','conditions']));
        $rules=['agreed_amount'=>['required','numeric','min:0.01','max:99999999999999.99'],'currency'=>['required','string','regex:/^[A-Za-z]{3,8}$/'],'rent_cadence'=>[$type==='rent'?'required':'nullable',Rule::in(self::CADENCES)],'security_deposit_amount'=>['nullable','numeric','min:0','max:99999999999999.99'],'rental_start_date'=>['nullable','date'],'rental_end_date'=>['nullable','date','after:rental_start_date'],'conditions'=>['nullable','string','max:5000']];$v=Validator::make($input,$rules)->validate();$v['currency']=Str::upper($v['currency']);if($type!=='rent'){$v['rent_cadence']=null;$v['security_deposit_amount']=null;$v['rental_start_date']=null;$v['rental_end_date']=null;}return $v;
    }

    private function contractTerms(Request $request,?object $current,?object $agreementRevision): array
    {
        $base=$current?['rent_amount'=>$current->rent_amount,'currency'=>$current->currency,'rent_cadence'=>$current->rent_cadence,'start_date'=>$current->start_date,'end_date'=>$current->end_date,'security_deposit_amount'=>$current->security_deposit_amount,'payment_due_day'=>$current->payment_due_day,'additional_terms'=>$current->additional_terms]:['rent_amount'=>$agreementRevision?->agreed_amount,'currency'=>$agreementRevision?->currency,'rent_cadence'=>$agreementRevision?->rent_cadence,'start_date'=>$agreementRevision?->rental_start_date,'end_date'=>$agreementRevision?->rental_end_date,'security_deposit_amount'=>$agreementRevision?->security_deposit_amount,'payment_due_day'=>null,'additional_terms'=>$agreementRevision?->conditions];$input=array_merge($base,$request->only(['rent_amount','currency','rent_cadence','start_date','end_date','security_deposit_amount','payment_due_day','additional_terms']));$v=Validator::make($input,['rent_amount'=>['required','numeric','min:0.01','max:99999999999999.99'],'currency'=>['required','string','regex:/^[A-Za-z]{3,8}$/'],'rent_cadence'=>['required',Rule::in(self::CADENCES)],'start_date'=>['required','date'],'end_date'=>['required','date','after:start_date'],'security_deposit_amount'=>['nullable','numeric','min:0','max:99999999999999.99'],'payment_due_day'=>['nullable','integer','between:1,28'],'additional_terms'=>['nullable','string','max:8000']])->validate();$v['currency']=Str::upper($v['currency']);return $v;
    }

    private function insertAgreementRevision(PropertyAgreement $a,int $number,array $terms,User $actor): void {DB::table('property_agreement_revisions')->insert(['property_agreement_id'=>$a->id,'revision_number'=>$number,'agreed_amount'=>$terms['agreed_amount'],'currency'=>$terms['currency'],'rent_cadence'=>$terms['rent_cadence']??null,'security_deposit_amount'=>$terms['security_deposit_amount']??null,'rental_start_date'=>$terms['rental_start_date']??null,'rental_end_date'=>$terms['rental_end_date']??null,'conditions'=>$terms['conditions']??null,'created_by_user_id'=>$actor->id,'created_by_name_snapshot'=>$actor->name,'created_at'=>now()]);}
    private function insertContractRevision(RentalContract $c,int $number,array $terms,User $actor): void {DB::table('rental_contract_revisions')->insert(['rental_contract_id'=>$c->id,'revision_number'=>$number,'rent_amount'=>$terms['rent_amount'],'currency'=>$terms['currency'],'rent_cadence'=>$terms['rent_cadence'],'start_date'=>$terms['start_date'],'end_date'=>$terms['end_date'],'security_deposit_amount'=>$terms['security_deposit_amount']??null,'payment_due_day'=>$terms['payment_due_day']??null,'additional_terms'=>$terms['additional_terms']??null,'created_by_user_id'=>$actor->id,'created_by_name_snapshot'=>$actor->name,'created_at'=>now()]);}
    private function agreementRevision(int $id,bool $locked=false): object {$q=DB::table('property_agreement_revisions')->where('property_agreement_id',$id)->orderByDesc('revision_number')->limit(1);if($locked)$q->lockForUpdate();$row=$q->first();abort_unless($row,409,'Agreement has no terms revision.');return $row;}
    private function contractRevision(int $id,bool $locked=false): object {$q=DB::table('rental_contract_revisions')->where('rental_contract_id',$id)->orderByDesc('revision_number')->limit(1);if($locked)$q->lockForUpdate();$row=$q->first();abort_unless($row,409,'Rental contract has no terms revision.');return $row;}

    private function agreementData(PropertyAgreement $a,User $user,bool $detail): array
    {
        $r=$this->agreementRevision($a->id);$accepted=DB::table('property_agreement_acceptances')->where('property_agreement_revision_id',$r->id)->pluck('user_id')->map(fn($id)=>(int)$id);$data=['id'=>$a->id,'reference'=>$a->reference,'property_id'=>$a->property_id,'message_thread_id'=>$a->message_thread_id,'viewing_booking_id'=>$a->viewing_booking_id,'requester_user_id'=>$a->requester_user_id,'advertiser_user_id'=>$a->advertiser_user_id,'transaction_type'=>$a->transaction_type,'status'=>$a->status,'current_revision'=>$this->agreementRevisionData($r),'requester_accepted'=>$accepted->contains((int)$a->requester_user_id),'advertiser_accepted'=>$accepted->contains((int)$a->advertiser_user_id),'my_accepted'=>$accepted->contains((int)$user->id),'can_revise'=>$a->status==='draft','can_accept'=>$a->status==='draft'&&!$accepted->contains((int)$user->id),'can_cancel'=>$a->status==='draft','accepted_at'=>$a->accepted_at?->toIso8601String(),'cancelled_at'=>$a->cancelled_at?->toIso8601String(),'cancellation_reason'=>$a->cancellation_reason,'rental_contract_id'=>RentalContract::query()->where('property_agreement_id',$a->id)->value('id'),'created_at'=>$a->created_at?->toIso8601String()];if($detail)$data['revisions']=DB::table('property_agreement_revisions')->where('property_agreement_id',$a->id)->orderByDesc('revision_number')->get()->map(fn($rev)=>array_merge($this->agreementRevisionData($rev),['acceptances'=>DB::table('property_agreement_acceptances')->where('property_agreement_revision_id',$rev->id)->orderBy('id')->get()->map(fn($x)=>['user_id'=>(int)$x->user_id,'party_role'=>$x->party_role,'accepted_at'=>$x->accepted_at])->values()]))->values();return $data;
    }
    private function contractData(RentalContract $c,User $user,bool $detail): array {$r=$this->contractRevision($c->id);$accepted=DB::table('rental_contract_acceptances')->where('rental_contract_revision_id',$r->id)->pluck('user_id')->map(fn($id)=>(int)$id);$data=['id'=>$c->id,'reference'=>$c->reference,'property_agreement_id'=>$c->property_agreement_id,'property_id'=>$c->property_id,'message_thread_id'=>$c->message_thread_id,'tenant_user_id'=>$c->tenant_user_id,'advertiser_user_id'=>$c->advertiser_user_id,'property_title'=>$c->property_title_snapshot,'property_address'=>$c->property_address_snapshot,'tenant_name'=>$c->tenant_name_snapshot,'advertiser_name'=>$c->advertiser_name_snapshot,'status'=>$c->status,'current_revision'=>$this->contractRevisionData($r),'tenant_accepted'=>$accepted->contains((int)$c->tenant_user_id),'advertiser_accepted'=>$accepted->contains((int)$c->advertiser_user_id),'my_accepted'=>$accepted->contains((int)$user->id),'can_revise'=>$c->status==='draft','can_accept'=>$c->status==='draft'&&!$accepted->contains((int)$user->id),'can_cancel'=>$c->status==='draft','can_terminate'=>$c->status==='active','activated_at'=>$c->activated_at?->toIso8601String(),'cancelled_at'=>$c->cancelled_at?->toIso8601String(),'terminated_at'=>$c->terminated_at?->toIso8601String(),'closure_reason'=>$c->closure_reason,'created_at'=>$c->created_at?->toIso8601String(),'in_app_only'=>true,'official_registration'=>false];if($detail)$data['revisions']=DB::table('rental_contract_revisions')->where('rental_contract_id',$c->id)->orderByDesc('revision_number')->get()->map(fn($rev)=>array_merge($this->contractRevisionData($rev),['acceptances'=>DB::table('rental_contract_acceptances')->where('rental_contract_revision_id',$rev->id)->orderBy('id')->get()->map(fn($x)=>['user_id'=>(int)$x->user_id,'party_role'=>$x->party_role,'accepted_at'=>$x->accepted_at])->values()]))->values();return $data;}
    private function agreementRevisionData(object $r): array {return ['id'=>(int)$r->id,'revision_number'=>(int)$r->revision_number,'agreed_amount'=>(float)$r->agreed_amount,'currency'=>$r->currency,'rent_cadence'=>$r->rent_cadence,'security_deposit_amount'=>$r->security_deposit_amount===null?null:(float)$r->security_deposit_amount,'rental_start_date'=>$r->rental_start_date,'rental_end_date'=>$r->rental_end_date,'conditions'=>$r->conditions,'created_by_user_id'=>(int)$r->created_by_user_id,'created_by_name'=>$r->created_by_name_snapshot,'created_at'=>$r->created_at];}
    private function contractRevisionData(object $r): array {return ['id'=>(int)$r->id,'revision_number'=>(int)$r->revision_number,'rent_amount'=>(float)$r->rent_amount,'currency'=>$r->currency,'rent_cadence'=>$r->rent_cadence,'start_date'=>$r->start_date,'end_date'=>$r->end_date,'security_deposit_amount'=>$r->security_deposit_amount===null?null:(float)$r->security_deposit_amount,'payment_due_day'=>$r->payment_due_day===null?null:(int)$r->payment_due_day,'additional_terms'=>$r->additional_terms,'created_by_user_id'=>(int)$r->created_by_user_id,'created_by_name'=>$r->created_by_name_snapshot,'created_at'=>$r->created_at];}

    private function canonicalParties(MessageThread $thread,Property $property): array {$ids=MessageThreadParticipant::query()->where('thread_id',$thread->id)->pluck('user_id')->map(fn($id)=>(int)$id)->unique()->values();abort_unless($ids->count()===2&&$ids->contains((int)$property->user_id),409,'Agreement requires the canonical two-party property conversation.');$requester=(int)$ids->first(fn($id)=>(int)$id!==(int)$property->user_id);abort_if($requester===(int)$property->user_id,409,'You cannot create an agreement with yourself.');return [$requester,(int)$property->user_id];}
    private function assertThreadParty(User $u,MessageThread $t): void {abort_unless(MessageThreadParticipant::query()->where('thread_id',$t->id)->where('user_id',$u->id)->exists(),404);}
    private function assertAgreementParty(User $u,PropertyAgreement $a): void {abort_unless(in_array((int)$u->id,[(int)$a->requester_user_id,(int)$a->advertiser_user_id],true),404);}
    private function assertContractParty(User $u,RentalContract $c): void {abort_unless(in_array((int)$u->id,[(int)$c->tenant_user_id,(int)$c->advertiser_user_id],true),404);}
    private function assertViewingLink(int $id,int $threadId,int $requesterId): void {$b=ViewingBooking::query()->findOrFail($id);abort_unless((int)$b->message_thread_id===$threadId&&(int)$b->requester_user_id===$requesterId&&$b->status==='completed',409,'Only a completed viewing from this property conversation can be linked.');}
    private function agreementRole(PropertyAgreement $a,User $u): string {return (int)$a->requester_user_id===(int)$u->id?'requester':'advertiser';}
    private function contractRole(RentalContract $c,User $u): string {return (int)$c->tenant_user_id===(int)$u->id?'tenant':'advertiser';}
    private function otherAgreementPartyId(PropertyAgreement $a,User $u): int {return (int)$a->requester_user_id===(int)$u->id?(int)$a->advertiser_user_id:(int)$a->requester_user_id;}
    private function otherContractPartyId(RentalContract $c,User $u): int {return (int)$c->tenant_user_id===(int)$u->id?(int)$c->advertiser_user_id:(int)$c->tenant_user_id;}
    private function latestAgreementForThread(int $threadId,bool $locked=false): ?PropertyAgreement {$q=PropertyAgreement::query()->where('message_thread_id',$threadId)->latest('id');if($locked)$q->lockForUpdate();return $q->first();}
    private function notifyAgreementOther(PropertyAgreement $a,User $actor,string $type,string $title,string $body): void {$this->notifications->create($this->otherAgreementPartyId($a,$actor),$type,$title,$body,'property_agreement',$a->id,['agreement_id'=>$a->id,'property_id'=>$a->property_id,'message_thread_id'=>$a->message_thread_id]);}
    private function notifyContractOther(RentalContract $c,User $actor,string $type,string $title,string $body): void {$this->notifications->create($this->otherContractPartyId($c,$actor),$type,$title,$body,'rental_contract',$c->id,['rental_contract_id'=>$c->id,'agreement_id'=>$c->property_agreement_id,'property_id'=>$c->property_id,'message_thread_id'=>$c->message_thread_id]);}
    private function lockKey(int $namespace,int $id): void {if(DB::connection()->getDriverName()==='pgsql')DB::select('SELECT pg_advisory_xact_lock(?, ?)',[$namespace,$id]);}
    private function reference(string $prefix): string {do{$ref=$prefix.'-'.Str::upper(Str::random(10));}while(PropertyAgreement::query()->where('reference',$ref)->exists()||RentalContract::query()->where('reference',$ref)->exists());return $ref;}
}
