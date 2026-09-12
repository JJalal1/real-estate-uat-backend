from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one anchor, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def replace_section(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{path}: missing section start {start!r}")
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit(f"{path}: missing section end {end!r}")
    if text.find(start, i + 1) >= 0:
        raise SystemExit(f"{path}: section start is not unique {start!r}")
    write(path, text[:i] + replacement + text[j:])


# Routes: authoritative listing financial config, pending Sai attestations, and assigned payment review detail.
routes = "backend-api-runtime/routes/financial_v1.php"
replace_once(
    routes,
    "    Route::post('/properties/{property}/submit', [FinancialPropertyController::class, 'submit']);\n\n    Route::get('/finance/payments/mine', [PropertyFinancialController::class, 'paymentsMine']);",
    "    Route::post('/properties/{property}/submit', [FinancialPropertyController::class, 'submit']);\n    Route::patch('/properties/{property}/financial-config', [PropertyFinancialController::class, 'configureListing']);\n\n    Route::get('/finance/payments/mine', [PropertyFinancialController::class, 'paymentsMine']);\n    Route::get('/finance/sai-attestations/pending', [PropertyFinancialController::class, 'pendingSaiAttestations']);",
)
replace_once(
    routes,
    "    Route::get('/admin/finance/summary', [PropertyFinancialController::class, 'adminSummary'])->middleware('permission:finance.view');",
    "    Route::get('/admin/finance/summary', [PropertyFinancialController::class, 'adminSummary'])->middleware('permission:finance.view');\n    Route::get('/admin/finance/payments/{payment}', [PropertyFinancialController::class, 'adminPayment'])->middleware('permission:payments.review');",
)

# Financial property wrapper: only validate rental finance when supplied on this mutation,
# and require complete rental finance before submission.
fpc = "backend-api-runtime/app/Http/Controllers/Api/FinancialPropertyController.php"
replace_once(
    fpc,
    "        $hasRentFinance=$request->hasAny(['monthly_rent','rental_term_months','advance_months'])\n            || $existing?->monthly_rent!==null || $existing?->rental_term_months!==null || $existing?->advance_months!==null;",
    "        $hasRentFinance=$request->hasAny(['monthly_rent','rental_term_months','advance_months']);",
)
replace_once(
    fpc,
    "        if($property->purpose==='rent' && ($property->monthly_rent!==null || $property->rental_term_months!==null || $property->advance_months!==null)){",
    "        if($property->purpose==='rent'){",
)

# Model relations used for N+1-safe financial payloads.
payment_model = "backend-api-runtime/app/Models/PropertyPayment.php"
replace_once(
    payment_model,
    "    public function financialTerm(): BelongsTo { return $this->belongsTo(PropertyDealFinancialTerm::class, 'deal_financial_term_id'); }\n}",
    "    public function financialTerm(): BelongsTo { return $this->belongsTo(PropertyDealFinancialTerm::class, 'deal_financial_term_id'); }\n    public function property(): BelongsTo { return $this->belongsTo(Property::class, 'property_id'); }\n}\n",
)
term_model = "backend-api-runtime/app/Models/PropertyDealFinancialTerm.php"
replace_once(
    term_model,
    "    public function advertiser(): BelongsTo { return $this->belongsTo(User::class, 'advertiser_user_id'); }\n}",
    "    public function advertiser(): BelongsTo { return $this->belongsTo(User::class, 'advertiser_user_id'); }\n    public function property(): BelongsTo { return $this->belongsTo(Property::class, 'property_id'); }\n}\n",
)

# Generic support workspace must actually expose and operate payment-review tasks.
support = "backend-api-runtime/app/Services/SupportTaskService.php"
replace_once(support, "use App\\Models\\Property;\n", "use App\\Models\\Property;\nuse App\\Models\\PropertyPayment;\n")
replace_once(
    support,
    "        $this->syncSupportCases();\n    }",
    "        $this->syncSupportCases();\n        // Payment tasks are projected immediately when proof is submitted.\n    }",
)
replace_once(
    support,
    "        $this->assertAssigneeCanReceive($actor,$task,$assignee);",
    "        if ($task->source_type==='payment_review' && !$assignee->hasPermission('payments.review')) {\n            throw ValidationException::withMessages(['user_id'=>['المهمة المالية تُسند لموظف دعم لديه صلاحية مراجعة المدفوعات.']]);\n        }\n        $this->assertAssigneeCanReceive($actor,$task,$assignee);",
)
replace_once(
    support,
    "        if($actor->hasPermission('listings.moderate'))$types[]='listing_review';\n        $query->whereIn('source_type',array_values(array_unique($types?:['__none__'])));",
    "        if($actor->hasPermission('listings.moderate'))$types[]='listing_review';\n        if($actor->hasPermission('payments.review'))$types[]='payment_review';\n        $query->whereIn('source_type',array_values(array_unique($types?:['__none__'])));",
)
replace_once(
    support,
    "        if($type==='listing_review'&&!$actor->hasPermission('listings.moderate'))abort(403);\n        if(in_array($type,['support_ticket','report','account_verification'],true)&&!$actor->hasPermission('support.handle_reports'))abort(403);",
    "        if($type==='listing_review'&&!$actor->hasPermission('listings.moderate'))abort(403);\n        if($type==='payment_review'&&!$actor->hasPermission('payments.review'))abort(403);\n        if(in_array($type,['support_ticket','report','account_verification'],true)&&!$actor->hasPermission('support.handle_reports'))abort(403);",
)
replace_once(
    support,
    "    public function projectSource(string $type, int $sourceId): ?SupportTask\n    {",
    "    public function projectPayment(PropertyPayment|int $payment): SupportTask\n    {\n        return app(FinancialSupportTaskService::class)->projectPayment($payment);\n    }\n\n    public function projectSource(string $type, int $sourceId): ?SupportTask\n    {",
)
replace_once(
    support,
    "            'support_ticket', 'report' => $this->projectSupportCase($sourceId),\n            default => null,",
    "            'support_ticket', 'report' => $this->projectSupportCase($sourceId),\n            'payment_review' => $this->projectPayment($sourceId),\n            default => null,",
)
replace_once(
    support,
    "    private function claimSource(User $actor, SupportTask $task): void\n    {\n        if($task->source_type==='listing_review'){","
    private function claimSource(User $actor, SupportTask $task): void\n    {\n        if($task->source_type==='payment_review'){\n            $payment=PropertyPayment::query()->lockForUpdate()->findOrFail($task->source_id);\n            if(!in_array($payment->status,['proof_submitted','under_review'],true))throw new ConflictHttpException('إثبات الدفع لم يعد بانتظار التحقق.');\n            if($payment->status!=='under_review')$payment->forceFill(['status'=>'under_review'])->save();\n            return;\n        }\n        if($task->source_type==='listing_review'){
",
)
replace_once(
    support,
    "    private function assignSource(SupportTask $task, User $assignee): void\n    {\n        if($task->source_type==='listing_review'){","
    private function assignSource(SupportTask $task, User $assignee): void\n    {\n        if($task->source_type==='payment_review'){\n            PropertyPayment::query()->whereKey($task->source_id)->whereIn('status',['proof_submitted','under_review'])->update(['status'=>'under_review','updated_at'=>now()]);\n            return;\n        }\n        if($task->source_type==='listing_review'){
",
)
replace_once(
    support,
    "    private function releaseSource(SupportTask $task): void\n    {\n        if($task->source_type==='listing_review'){",
    "    private function releaseSource(SupportTask $task): void\n    {\n        if($task->source_type==='payment_review'){PropertyPayment::query()->whereKey($task->source_id)->where('status','under_review')->update(['status'=>'proof_submitted','updated_at'=>now()]);return;}\n        if($task->source_type==='listing_review'){",
)

# PropertyFinancialController: safe reviewer access, rental config, pending oath list,
# complete deal/payment payloads, and review-note enforcement.
controller = "backend-api-runtime/app/Http/Controllers/Api/PropertyFinancialController.php"
replace_once(controller, "use Illuminate\\Validation\\Rule;\n", "use Illuminate\\Validation\\Rule;\nuse Illuminate\\Validation\\ValidationException;\n")

replace_section(
    controller,
    "    public function proof(Request $request, PropertyPayment $payment): Response\n",
    "    public function paymentsMine(Request $request): JsonResponse\n",
    "    public function proof(Request $request, PropertyPayment $payment): Response\n    {\n        /** @var User $user */ $user=$request->user();\n        $this->assertPaymentEvidenceAccess($request,$payment,$user);\n        abort_unless($payment->proof_path,404);\n        return $this->storage->responsePrivate($payment->proof_path,$payment->proof_original_name ?: 'payment-proof');\n    }\n\n",
)
replace_once(
    controller,
    "        $rows=PropertyPayment::query()->with('method')->where('payer_user_id',$user->id)->latest('id')->limit(250)->get();",
    "        $rows=PropertyPayment::query()->with(['method','financialTerm','property'])->where('payer_user_id',$user->id)->latest('id')->limit(250)->get();",
)
replace_once(
    controller,
    "        $deals=PropertyDealFinancialTerm::query()->where('advertiser_user_id',$user->id)->latest('id')->limit(250)->get();",
    "        $deals=PropertyDealFinancialTerm::query()->with('property')->where('advertiser_user_id',$user->id)->latest('id')->limit(250)->get();",
)

insert_before_confirm = r'''    public function configureListing(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$property->user_id===(int)$user->id,403);
        if($property->status==='published'||in_array($property->review_status,['submitted','under_review','approved','rejected_blocked'],true)){
            throw new ConflictHttpException('عدّل البيانات المالية أثناء المسودة أو بعد إعادتها للتصحيح.');
        }
        $validated=$request->validate([
            'price_display_mode'=>['nullable',Rule::in(['includes_sai','excludes_sai'])],
            'monthly_rent'=>['nullable','numeric','gt:0','max:9999999999999'],
            'rental_term_months'=>['nullable','integer','min:1','max:24'],
            'advance_months'=>['nullable','integer','min:1','max:24'],
        ]);
        if($property->purpose==='rent'){
            $monthly=(float)($validated['monthly_rent']??$property->monthly_rent??0);
            $term=(int)($validated['rental_term_months']??$property->rental_term_months??0);
            $advance=(int)($validated['advance_months']??$property->advance_months??0);
            if($monthly<=0||$term<1||$term>24||$advance<1||$advance>24){
                throw ValidationException::withMessages(['financial'=>['أكمل الإيجار الشهري ومدة التأجير وأشهر المقدم.']]);
            }
            if($advance>$term)throw ValidationException::withMessages(['advance_months'=>['عدد أشهر المقدم لا يمكن أن يتجاوز مدة التأجير.']]);
            $property->monthly_rent=$monthly;$property->rental_term_months=$term;$property->advance_months=$advance;$property->price=round($monthly*$advance,2);
        }else{
            $property->monthly_rent=null;$property->rental_term_months=null;$property->advance_months=null;
        }
        if($request->exists('price_display_mode'))$property->price_display_mode=$validated['price_display_mode']??null;
        $property->saveQuietly();
        $this->audit->record($user,'listing.financial_config_updated',$property,[
            'price_display_mode'=>$property->price_display_mode,'monthly_rent'=>$property->monthly_rent,
            'rental_term_months'=>$property->rental_term_months,'advance_months'=>$property->advance_months,
        ],$request,$user->id);
        return response()->json(['message'=>'تم تحديث بيانات السعر والتسوية.','data'=>[
            'property_id'=>$property->id,'price'=>(float)$property->price,'price_display_mode'=>$property->price_display_mode,
            'monthly_rent'=>$property->monthly_rent!==null?(float)$property->monthly_rent:null,
            'rental_term_months'=>$property->rental_term_months,'advance_months'=>$property->advance_months,
        ]]);
    }

    public function pendingSaiAttestations(Request $request): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        $rows=Property::query()->withoutGlobalScopes()->where('user_id',$user->id)->where('status','published')->whereNotNull('current_sai_term_id')
            ->whereNotExists(function($q):void{$q->selectRaw('1')->from('property_sai_attestations as a')->whereColumn('a.property_id','properties.id')->whereColumn('a.sai_term_id','properties.current_sai_term_id');})
            ->latest('published_at')->limit(100)->get(['id','title','current_sai_term_id']);
        return response()->json(['data'=>$rows->map(fn(Property $p)=>[
            'property_id'=>$p->id,'property_title'=>$p->title,'sai_term_id'=>(int)$p->current_sai_term_id,
            'text'=>PropertyFinancialService::SAI_ATTESTATION_TEXT,
        ])->values()]);
    }

'''
replace_once(
    controller,
    "    public function confirmDirect(Request $request, PropertyAgreement $agreement): JsonResponse\n",
    insert_before_confirm + "    public function confirmDirect(Request $request, PropertyAgreement $agreement): JsonResponse\n",
)

replace_section(
    controller,
    "    public function attestSai(Request $request, Property $property): JsonResponse\n",
    "    public function review(Request $request, PropertyPayment $payment): JsonResponse\n",
    "    public function attestSai(Request $request, Property $property): JsonResponse\n    {\n        /** @var User $user */ $user=$request->user();\n        $request->validate(['accepted'=>['required','accepted']]);\n        $this->finance->attestSai($property,$user,$request);\n        return response()->json(['message'=>'تم تسجيل إقرار السعي.']);\n    }\n\n    public function adminPayment(Request $request, PropertyPayment $payment): JsonResponse\n    {\n        /** @var User $actor */ $actor=$request->user();\n        $this->assertAssignedPaymentReviewer($request,$payment,$actor);\n        return response()->json(['data'=>$this->paymentData($payment,$actor)]);\n    }\n\n",
)
replace_once(
    controller,
    "        abort_unless($actor->hasPermission('payments.review'),403);\n        if ($actor->hasRole('support_manager')",
    "        abort_unless($actor->hasPermission('payments.review'),403);\n        if(in_array($validated['decision'],['correction','reject'],true)&&mb_strlen(trim((string)($validated['note']??'')))<3){\n            throw ValidationException::withMessages(['note'=>['اكتب سببًا واضحًا عند طلب التصحيح أو رفض الإثبات.']]);\n        }\n        if ($actor->hasRole('support_manager')",
)

new_deal_data = r'''    private function dealData(PropertyDealFinancialTerm $term, User $viewer, bool $includeMethods): array
    {
        $term->loadMissing('property');
        $buyerPays=in_array($term->sai_payer,['buyer','tenant'],true);
        $isBuyer=(int)$viewer->id===(int)$term->buyer_user_id;
        $isAdvertiser=(int)$viewer->id===(int)$term->advertiser_user_id;
        $fullRequired=round((float)$term->base_amount+($buyerPays?(float)$term->sai_total_amount:0),2);
        $saiRequired=0.0;
        if($buyerPays&&$isBuyer)$saiRequired=round((float)$term->sai_total_amount,2);
        elseif(!$buyerPays&&$isAdvertiser)$saiRequired=round((float)$term->platform_share_amount,2);
        $canPayFull=$isBuyer&&$fullRequired>0;
        $canPaySaiOnly=$saiRequired>0;
        $data=[
            'id'=>$term->id,'agreement_id'=>$term->property_agreement_id,'property_id'=>$term->property_id,
            'property_title'=>$term->property?->title ?: 'العقار','transaction_type'=>$term->transaction_type,
            'advertiser_type'=>$term->advertiser_type,'currency'=>$term->currency,'base_amount'=>(float)$term->base_amount,
            'monthly_rent'=>$term->monthly_basis_amount!==null?(float)$term->monthly_basis_amount:null,'rental_term_months'=>$term->rental_term_months,
            'advance_months'=>$term->advance_months,'sai_payer'=>$term->sai_payer,'sai_total_amount'=>(float)$term->sai_total_amount,
            'required_full_payment'=>$fullRequired,'required_sai_payment'=>$saiRequired,'can_pay_full'=>$canPayFull,'can_pay_sai_only'=>$canPaySaiOnly,
            'price_display_mode'=>$term->price_display_mode,'is_buyer'=>$isBuyer,'is_advertiser'=>$isAdvertiser,'frozen_at'=>$term->frozen_at?->toIso8601String(),
        ];
        if($isAdvertiser){
            $data['platform_share_amount']=(float)$term->platform_share_amount;$data['advertiser_sai_share_amount']=(float)$term->advertiser_sai_share_amount;
        }
        if($includeMethods){
            $methodAmount=$canPayFull?$fullRequired:$saiRequired;
            $data['payment_methods']=$methodAmount>0?$this->finance->paymentMethods($methodAmount,$term->currency):[];
            $payments=PropertyPayment::query()->with(['method','financialTerm','property'])->where('deal_financial_term_id',$term->id)->latest('id')->limit(50)->get();
            $data['payments']=$payments->map(fn(PropertyPayment $p)=>$this->paymentData($p,$viewer))->values();
            $receivable=PropertyPlatformReceivable::query()->where('deal_financial_term_id',$term->id)->latest('id')->first();
            $data['receivable']=$receivable?$this->receivableData($receivable):null;
        }
        return $data;
    }

'''
replace_section(controller, "    private function dealData(PropertyDealFinancialTerm $term, User $viewer, bool $includeMethods): array\n", "    private function paymentData(PropertyPayment $payment, User $viewer): array\n", new_deal_data)

new_payment_data = r'''    private function paymentData(PropertyPayment $payment, User $viewer): array
    {
        $payment->loadMissing(['method','financialTerm','property']);
        $canSeeEvidence=(int)$payment->payer_user_id===(int)$viewer->id||$viewer->is_platform_owner||$viewer->hasRole('super_admin')||$viewer->hasPermission('finance.manage')||$viewer->hasPermission('payments.review');
        return [
            'id'=>$payment->id,'reference'=>$payment->reference,'agreement_id'=>$payment->financialTerm?->property_agreement_id,
            'property_id'=>$payment->property_id,'property_title'=>$payment->property?->title,'mode'=>$payment->mode,'status'=>$payment->status,
            'required_amount'=>(float)$payment->required_amount,'currency'=>$payment->currency,'payment_method'=>$payment->method?[
                'id'=>$payment->method->id,'key'=>$payment->method->key,'name_ar'=>$payment->method->name_ar,'asset_key'=>$payment->method->asset_key,
                'beneficiary_name'=>$payment->method->beneficiary_name,'destination_label'=>$payment->method->destination_label,'destination_value'=>$payment->method->destination_value,
                'instructions_ar'=>$payment->method->instructions_ar,'requires_sender_phone'=>$payment->method->requires_sender_phone,
                'requires_provider_reference'=>$payment->method->requires_provider_reference,
            ]:null,'provider_reference'=>$canSeeEvidence?$payment->provider_reference:null,'sender_name'=>$canSeeEvidence?$payment->sender_name:null,'sender_phone'=>$canSeeEvidence?$payment->sender_phone:null,
            'has_proof'=>$payment->proof_path!==null,'proof_url'=>$canSeeEvidence&&$payment->proof_path?'/api/finance/payments/'.$payment->id.'/proof':null,
            'review_note'=>$payment->review_note,'created_at'=>$payment->created_at?->toIso8601String(),'submitted_at'=>$payment->submitted_at?->toIso8601String(),'confirmed_at'=>$payment->confirmed_at?->toIso8601String(),
        ];
    }

'''
replace_section(controller, "    private function paymentData(PropertyPayment $payment, User $viewer): array\n", "    private function receivableData(PropertyPlatformReceivable $r): array\n", new_payment_data)

helper = r'''    private function assertPaymentEvidenceAccess(Request $request, PropertyPayment $payment, User $actor): void
    {
        if((int)$payment->payer_user_id===(int)$actor->id||$actor->is_platform_owner||$actor->hasRole('super_admin')||$actor->hasPermission('finance.manage'))return;
        $this->assertAssignedPaymentReviewer($request,$payment,$actor);
    }

    private function assertAssignedPaymentReviewer(Request $request, PropertyPayment $payment, User $actor): void
    {
        abort_unless($actor->hasPermission('payments.review'),403);
        if($actor->hasRole('support_manager')&&!$actor->is_platform_owner&&!$actor->hasRole('super_admin')&&!$request->boolean('acting_as_agent')){
            throw new ConflictHttpException('فعّل وضع «العمل كموظف دعم» قبل مراجعة إثبات الدفع بنفسك.');
        }
        if($actor->is_platform_owner||$actor->hasRole('super_admin'))return;
        $task=SupportTask::query()->where('source_type','payment_review')->where('source_id',$payment->id)->first();
        abort_unless($task&&(int)$task->assigned_to_user_id===(int)$actor->id,403,'يجب استلام مهمة التحقق أو إسنادها لك أولاً.');
    }

'''
replace_once(controller, "    private function receivableData(PropertyPlatformReceivable $r): array\n", helper + "    private function receivableData(PropertyPlatformReceivable $r): array\n")

# Acceptance tests for rental configuration, oath snapshot, and support payment-review ownership.
test = "backend-api-runtime/tests/Feature/FinancialV1ApiTest.php"
replace_once(test, "use App\\Models\\Role;\n", "use App\\Models\\Role;\nuse App\\Models\\SupportTask;\n")
replace_once(test, "use Illuminate\\Support\\Facades\\Hash;\n", "use Illuminate\\Support\\Facades\\Hash;\nuse App\\Services\\PropertyFinancialService;\nuse App\\Services\\SupportTaskService;\n")
new_tests = r'''
    public function test_rental_financial_configuration_is_complete_and_snapshotted_on_listing(): void
    {
        [$advertiser, $headers] = $this->user('financial-rent-owner@example.test', '+967772000041');
        $property = $this->property($advertiser, 1_000_000, 'Financial rent config');
        $property->forceFill(['purpose'=>'rent','status'=>'draft','review_status'=>'draft','published_at'=>null])->saveQuietly();

        $this->withHeaders($headers)->patchJson("/api/properties/{$property->id}/financial-config", [
            'monthly_rent'=>250000,
            'rental_term_months'=>12,
            'advance_months'=>3,
            'price_display_mode'=>'excludes_sai',
        ])->assertOk()
          ->assertJsonPath('data.price', 750000)
          ->assertJsonPath('data.monthly_rent', 250000)
          ->assertJsonPath('data.rental_term_months', 12)
          ->assertJsonPath('data.advance_months', 3);

        $this->assertDatabaseHas('properties', [
            'id'=>$property->id,'purpose'=>'rent','price'=>750000,
            'monthly_rent'=>250000,'rental_term_months'=>12,'advance_months'=>3,
            'price_display_mode'=>'excludes_sai',
        ]);
        $this->withHeaders($headers)->patchJson("/api/properties/{$property->id}/financial-config", [
            'monthly_rent'=>250000,'rental_term_months'=>2,'advance_months'=>3,
        ])->assertStatus(422);
    }

    public function test_published_sai_attestation_uses_exact_snapshot_and_disappears_from_pending(): void
    {
        [$advertiser, $headers] = $this->user('financial-oath-owner@example.test', '+967772000042');
        $property = $this->property($advertiser, 100_000_000, 'Financial oath');
        $term = $this->term($property, 'seller');
        $property->forceFill(['current_sai_term_id'=>$term->id])->saveQuietly();

        $this->withHeaders($headers)->getJson('/api/finance/sai-attestations/pending')
            ->assertOk()->assertJsonFragment(['property_id'=>$property->id,'text'=>PropertyFinancialService::SAI_ATTESTATION_TEXT]);
        $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/sai-attestation", ['accepted'=>false])->assertStatus(422);
        $this->withHeaders($headers)->postJson("/api/properties/{$property->id}/sai-attestation", ['accepted'=>true])->assertOk();
        $this->assertDatabaseHas('property_sai_attestations', [
            'property_id'=>$property->id,'sai_term_id'=>$term->id,'user_id'=>$advertiser->id,
            'text_snapshot'=>PropertyFinancialService::SAI_ATTESTATION_TEXT,
        ]);
        $this->withHeaders($headers)->getJson('/api/finance/sai-attestations/pending')->assertOk()->assertJsonMissing(['property_id'=>$property->id]);
    }

    public function test_payment_review_task_is_visible_claimed_and_reviewed_only_by_assigned_agent(): void
    {
        [$agreementId, $property, , $buyer, , ] = $this->acceptedSaleDeal('buyer');
        $termId=(int)DB::table('property_deal_financial_terms')->where('property_agreement_id',$agreementId)->value('id');
        $methodId=(int)DB::table('property_payment_methods')->value('id');
        $paymentId=(int)DB::table('property_payments')->insertGetId([
            'reference'=>'PAY-TEST-REVIEW','deal_financial_term_id'=>$termId,'property_id'=>$property->id,
            'payer_user_id'=>$buyer->id,'advertiser_user_id'=>$property->user_id,'payment_method_id'=>$methodId,
            'mode'=>'platform_sai_only','status'=>'proof_submitted','required_amount'=>900000,'currency'=>'YER',
            'submitted_at'=>now(),'created_at'=>now(),'updated_at'=>now(),
        ]);
        app(SupportTaskService::class)->projectPayment($paymentId);

        [$agent, $agentHeaders] = $this->user('financial-support-agent@example.test', '+967772000043');
        $supportRole=Role::query()->where('key','support_agent')->firstOrFail();
        $agent->roles()->sync([$supportRole->id=>['assigned_by_user_id'=>null,'created_at'=>now()]]);

        $this->withHeaders($agentHeaders)->getJson("/api/admin/finance/payments/$paymentId")->assertForbidden();
        $inbox=$this->withHeaders($agentHeaders)->getJson('/api/admin/support/tasks?scope=inbox&type=payment_review')->assertOk();
        $taskId=(int)$inbox->json('data.0.id');
        $this->assertGreaterThan(0,$taskId);
        $this->withHeaders($agentHeaders)->postJson("/api/admin/support/tasks/$taskId/claim")->assertOk()->assertJsonPath('data.is_mine',true);
        $this->withHeaders($agentHeaders)->getJson("/api/admin/finance/payments/$paymentId")->assertOk()->assertJsonPath('data.status','under_review');
        $this->withHeaders($agentHeaders)->postJson("/api/admin/finance/payments/$paymentId/review",['decision'=>'correction','note'=>'صورة الإثبات غير واضحة'])->assertOk()->assertJsonPath('data.status','correction_required');
        $this->assertDatabaseHas('support_tasks',['id'=>$taskId,'source_type'=>'payment_review','status'=>'waiting_user','assigned_to_user_id'=>$agent->id]);
    }

'''
replace_once(test, "    private function acceptedSaleDeal(string $payer): array\n", new_tests + "    private function acceptedSaleDeal(string $payer): array\n")

print("Financial V1 backend finalization patch applied")
