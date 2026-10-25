<?php

namespace App\Console\Commands;

use App\Models\AccountVerificationProfile;
use App\Models\AuditLog;
use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use App\Services\ListingImageService;
use Illuminate\Console\Command;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

/** Explicit CLI-only acceptance; no HTTP route, scheduler or reusable credential. */
class UatRoleJourneys extends Command
{
    public const LIVE_RUN = '2026-10-25-109-v3';
    protected $signature = 'uat:role-journeys {--run=} {--base-url=}';
    protected $description = 'One-shot synthetic UAT role/API/Storage acceptance; never Production';
    private array $actors = [];
    private array $bearers = [];
    private array $receipts = [];
    private string $base;
    private string $run;
    private string $prefix;
    private float $started;

    public function handle(): int
    {
        $this->base = rtrim((string) $this->option('base-url'), '/');
        $this->run = (string) $this->option('run');
        // Never accept a caller-selected host, remote URL, existing user or ID.
        if (! preg_match('#^http://127\.0\.0\.1:[0-9]{2,5}$#D', $this->base)) return self::FAILURE;
        $ci = app()->environment('testing') && $this->run === 'disposable-ci';
        $live = app()->environment('staging') && $this->run === self::LIVE_RUN
            && env('UAT_EXECUTIVE_JOURNEY_RUN') === self::LIVE_RUN
            && parse_url((string) config('services.supabase_storage.url'), PHP_URL_HOST) === 'ipxsgxsqzthpgthwvdno.supabase.co'
            && app(CloudAssetStorageService::class)->cloudEnabled();
        if (! $ci && ! $live) return self::FAILURE;
        $this->prefix = 'uat-109-'.str_replace(['-','.'], '', $this->run).'-';
        $this->started = microtime(true);
        $fresh = DB::transaction(function (): bool {
            if (DB::getDriverName() === 'pgsql') DB::select('select pg_advisory_xact_lock(109, 20261024)');
            if (AuditLog::where('action','uat.role_journeys.started')->where('metadata->release_run',$this->run)->exists()) return false;
            app(AuditLogService::class)->record(null, 'uat.role_journeys.started', null, ['release_run'=>$this->run]);
            return true;
        });
        if (! $fresh) {
            $finished = AuditLog::where('action','uat.role_journeys.finished')->where('metadata->release_run',$this->run)->latest('id')->first();
            $result = $finished?->metadata['result'] ?? [];
            $this->line('AQER_UAT_ROLE_JOURNEYS '.json_encode(['run'=>$this->run,'status'=>'already-started-no-replay',
                'previous_result'=>$result['status'] ?? 'incomplete']));
            return ($result['status'] ?? null) === 'passed' && ($result['cleanup'] ?? false) === true ? self::SUCCESS : self::FAILURE;
        }
        $passed = false;
        try {
            if ($live) $this->retirePreviousSyntheticRun();
            foreach (['publisher'=>'broker','other'=>null,'other_publisher'=>'broker','reviewer'=>'support_agent','second_reviewer'=>'support_agent','manager'=>'support_manager'] as $name=>$role) {
                $this->createActor($name, $role);
            }
            $this->journeys();
            $passed = true;
        } catch (Throwable $error) {
            // HTTP exception text may contain a URL/body. Emit only the class
            // and case receipt; no exception/body/headers/credentials.
            $this->receipts[] = ['case'=>'execution_exception','type'=>class_basename($error),'passed'=>false];
        } finally {
            $cleanup = $this->disableFixtures();
            $passed = $passed && $cleanup;
            $summary = ['run'=>$this->run,'status'=>$passed ? 'passed' : 'failed','transport'=>'actual-loopback-http',
                'cloud_storage'=>$live,'otp_login_tested'=>false,'actor_count'=>count($this->actors),
                'cleanup'=>$cleanup,'elapsed_ms'=>round((microtime(true)-$this->started)*1000),'cases'=>$this->receipts];
            app(AuditLogService::class)->record(null,'uat.role_journeys.finished',null,['release_run'=>$this->run,'result'=>$summary]);
            $this->line('AQER_UAT_ROLE_JOURNEYS '.json_encode($summary, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        }
        return $passed ? self::SUCCESS : self::FAILURE;
    }

    private function createActor(string $key, ?string $role): void
    {
        $email = $this->prefix.$key.'@example.invalid';
        // A collision is never a reason to reuse or modify an existing actor.
        if (User::where('email',$email)->exists()) throw new RuntimeException('fixture_collision');
        $actor = User::create(['name'=>'UAT synthetic '.$key,'email'=>$email,
            'phone'=>'+120255501'.(91 + count($this->actors)),'password'=>Str::random(96),
            'phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,
            'account_status'=>'active','account_type'=>$role === 'broker' ? 'broker' : 'regular']);
        $this->actors[$key] = $actor;
        $ids = Role::whereIn('key', array_filter(['registered_user',$role]))->pluck('id');
        if ($ids->count() !== ($role === null ? 1 : 2)) throw new RuntimeException('fixture_roles_missing');
        $actor->roles()->sync($ids->mapWithKeys(fn ($id) => [$id=>['created_at'=>now()]]));
        if ($role === 'broker') AccountVerificationProfile::create(['user_id'=>$actor->id,'type'=>'broker',
            'status'=>'approved','details'=>[],'submitted_at'=>now(),'reviewed_at'=>now()]);
        $issued = app(ApiTokenService::class)->issue($actor, request(), $this->prefix.'acceptance');
        $actor->apiTokens()->where('name',$this->prefix.'acceptance')->update(['expires_at'=>now()->addMinutes(10)]);
        $this->bearers[$key] = $issued['plain_text_token'];
        app(AuditLogService::class)->record(null,'uat.role_journeys.fixture_created',$actor,['release_run'=>$this->run,'fixture'=>$key]);
    }

    private function wire(string $case, ?string $actor, string $method, string $path, array $data = [], int|array $expected = 200, ?string $image = null, string $imageField = 'image'): Response
    {
        if (! str_starts_with($path, '/api/') || str_contains($path, '..') || count($this->receipts) > 150
            || microtime(true) - $this->started > 480) throw new RuntimeException('probe_bound');
        DB::disconnect(); // CLI fixture bookkeeping must not occupy a worker's pool slot.
        $request = Http::acceptJson()->withUserAgent('Aqer-UAT-role-probe/1.0')
            ->connectTimeout(5)->timeout(40)->withoutRedirecting();
        if ($actor !== null) $request->withToken($this->bearers[$actor]);
        if ($image !== null) $request->attach($imageField, $image, 'synthetic.jpg', ['Content-Type'=>'image/jpeg']);
        $started = hrtime(true);
        $response = $image !== null ? $request->post($this->base.$path, $data)
            : $request->send($method, $this->base.$path, in_array($method,['GET','HEAD'],true) ? [] : ['json'=>$data]);
        $okay = in_array($response->status(), (array) $expected, true);
        $this->receipts[] = ['case'=>$case,'status'=>$response->status(),'expected'=>$expected,'passed'=>$okay,
            'elapsed_ms'=>round((hrtime(true)-$started)/1_000_000),'bytes'=>strlen($response->body()),
            'validation_fields'=>$okay ? [] : array_keys((array) $response->json('errors', []))];
        if (! $okay) throw new RuntimeException($case);
        return $response;
    }

    private function check(bool $okay, string $case): void
    {
        $this->receipts[] = ['case'=>$case,'passed'=>$okay];
        if (! $okay) throw new RuntimeException($case);
    }

    private function journeys(): void
    {
        foreach (array_keys($this->actors) as $actor) $this->wire('authenticated_'.$actor,$actor,'GET','/api/auth/me');
        $this->wire('broker_cannot_enter_platform_settings','publisher','GET','/api/admin/settings',[],403);
        $this->wire('support_manager_cannot_enter_finance','manager','GET','/api/admin/finance/summary',[],403);
        $this->wire('regular_cannot_upload_professional_photo','other','POST','/api/broker/profile/photo',[],403,$this->syntheticJpeg(6),'photo');
        $this->wire('professional_photo_upload','publisher','POST','/api/broker/profile/photo',[],200,$this->syntheticJpeg(6),'photo');
        $profilePath = $this->actors['publisher']->fresh()->public_professional_photo_path;
        $profilePhoto = $this->wire('public_professional_photo_is_sanitized',null,'GET','/api/advertisers/'.$this->actors['publisher']->id.'/photo');
        $this->check(str_starts_with($profilePhoto->body(),"\xff\xd8") && !str_contains($profilePhoto->body(),'Exif')
            && !str_contains($profilePhoto->body(),'UAT_PRIVATE_CAMERA'),'professional_photo_metadata_removed');
        $key = (string) Str::uuid(); $first = (string) Str::uuid(); $second = (string) Str::uuid();
        $url = '/api/listing-editor-drafts/'.$key;
        $payload = ['checkpoint_key'=>(string)Str::uuid(),'media_version'=>1,'type'=>'office','purpose'=>'rent',
            'latitude'=>15.123456,'longitude'=>44.654321,'image_order'=>[$first,$second],
            'fields'=>['title'=>'مسودة اصطناعية لانقطاع الشبكة','area'=>'65']];
        $saved = $this->wire('draft_save','publisher','PUT',$url,['payload'=>$payload,'expected_revision'=>0]);
        $this->check($saved->json('data.revision') === 1, 'draft_revision_one');
        $this->wire('lost_response_exact_retry','publisher','PUT',$url,['payload'=>$payload,'expected_revision'=>0]);
        $changed = $payload; $changed['fields']['title'] = 'must not replace confirmed text';
        $this->wire('stale_changed_checkpoint_conflict','publisher','PUT',$url,['payload'=>$changed,'expected_revision'=>0],409);
        $restored = $this->wire('draft_restore','publisher','GET',$url);
        $this->check($restored->json('data.payload.fields.title') === $payload['fields']['title'], 'draft_text_preserved');
        $this->wire('other_cannot_read_draft','other','GET',$url,[],404);
        $this->wire('unverified_actor_cannot_write_draft','other','PUT',$url,['payload'=>$payload,'expected_revision'=>1],403);
        $this->wire('other_publisher_has_no_matching_revision','other_publisher','PUT',$url,['payload'=>$payload,'expected_revision'=>1],409);
        $otherPayload = $payload;
        $otherPayload['checkpoint_key'] = (string)Str::uuid();
        $otherPayload['fields']['title'] = 'مسودة منفصلة للحساب الآخر';
        $otherPayload['image_order'] = [];
        $this->wire('same_uuid_is_separate_account_namespace','other_publisher','PUT',$url,['payload'=>$otherPayload,'expected_revision'=>0]);
        $ownAgain = $this->wire('original_account_draft_unchanged','publisher','GET',$url);
        $this->check($ownAgain->json('data.payload.fields.title') === $payload['fields']['title'] && $ownAgain->json('data.revision') === 1,'other_namespace_cannot_change_original');
        $source = $this->syntheticJpeg(6);
        $this->wire('first_real_image_upload','publisher','POST',$url.'/images/'.$first,['expected_revision'=>1],200,$source);
        $retry = $this->wire('image_upload_retry_no_duplicate','publisher','POST',$url.'/images/'.$first,['expected_revision'=>1],200,$source);
        $this->check($retry->json('data.revision') === 2 && count($retry->json('data.images')) === 1, 'one_image_after_retry');
        $uploaded = $this->wire('second_real_image_upload','publisher','POST',$url.'/images/'.$second,['expected_revision'=>2],200,$this->syntheticJpeg(1));
        $this->check(count($uploaded->json('data.images')) === 2, 'two_images_after_upload');
        $this->wire('other_cannot_read_draft_image','other','GET',$url.'/images/'.$first,[],404);
        $this->wire('staff_cannot_read_foreign_editor_draft','reviewer','GET',$url.'/images/'.$first,[],404);
        $safe = $this->wire('owner_sanitized_draft_image','publisher','GET',$url.'/images/'.$first.'?variant=thumb');
        $this->check(! str_contains($safe->body(),'Exif') && ! str_contains($safe->body(),'UAT_PRIVATE_CAMERA'), 'real_exif_camera_gps_removed');
        $dimensions = getimagesizefromstring($safe->body());
        $this->check($dimensions[1] > $dimensions[0] && max($dimensions[0],$dimensions[1]) <= 320,'real_exif_orientation_preserved');
        $this->check(str_contains((string)$safe->header('Cache-Control'),'no-store'), 'draft_image_private_no_store');
        $originalPath = ListingEditorDraft::where('user_id',$this->actors['publisher']->id)->where('client_key',$key)->firstOrFail()->images[$first];
        $this->check(hash_equals(hash('sha256',$source),hash('sha256',app(CloudAssetStorageService::class)->readBytes($originalPath,true))), 'private_original_sha256_preserved');
        $input = ['listing_input_version'=>9,'title'=>'UAT وحدة مكتبية تجريبية '.$this->run,'description'=>'بيانات اختبار اصطناعية لا تمثل عقارًا حقيقيًا',
            'type'=>'office','purpose'=>'rent','price'=>75000,'monthly_rent'=>75000,'currency'=>'YER','area_value'=>65,'area_unit'=>'sqm',
            'floor_number'=>'0','has_parking'=>0,'building_facade'=>'north',
            'address'=>'صنعاء UAT '.$this->run.' مبنى اصطناعي مستقل','building_reference'=>$this->prefix.'building','unit_number'=>'109',
            'contact_phone'=>'700000000','contact_whatsapp'=>'700000000',
            'latitude'=>15.123456,'longitude'=>44.654321,'editor_draft_key'=>$key,'editor_draft_revision'=>3];
        $created = $this->wire('canonical_v9_listing_create','publisher','POST','/api/properties',$input,201);
        $id = (int) $created->json('data.id'); $images = $created->json('data.images');
        $this->check(count($images) === 2 && $created->json('data.status') === 'draft', 'new_listing_private_two_images');
        $this->check((float) $created->json('data.latitude') === 15.123456 && (float) $created->json('data.longitude') === 44.654321,'photo_gps_does_not_change_listing_pin');
        $this->wire('lost_listing_create_response_no_duplicate','publisher','POST','/api/properties',$input,409);
        $imageId = (int) $images[0]['id'];
        $this->wire('public_cannot_read_unpublished',null,'GET','/api/property-media/'.$imageId.'?variant=thumb',[],404);
        $this->wire('other_cannot_read_unpublished','other','GET','/api/property-media/'.$imageId.'?variant=thumb',[],404);
        $this->wire('original_variant_denied','publisher','GET','/api/property-media/'.$imageId.'?variant=original',[],422);
        $this->wire('other_cannot_edit_property','other','POST','/api/properties/'.$id,['title'=>'forbidden'],403);
        $reordered = array_reverse(array_column($images,'id'));
        $payload['checkpoint_key'] = (string) Str::uuid(); $payload['image_order'] = array_map(fn ($n) => 'property-'.$n, $reordered);
        $this->wire('reorder_checkpoint','publisher','PUT',$url,['payload'=>$payload,'expected_revision'=>4,'property_id'=>$id]);
        $input['editor_draft_revision'] = 5;
        $edited = $this->wire('apply_image_order_primary','publisher','POST','/api/properties/'.$id,$input);
        $this->check(array_column($edited->json('data.images'),'id') === $reordered && $edited->json('data.images.0.is_primary') === true,'real_image_order_primary_roundtrip');
        // Remove one promoted photo while retaining a real independent one.
        $removedPath = DB::table('property_images')->where('id',$reordered[1])->value('path');
        $payload['checkpoint_key'] = (string) Str::uuid(); $payload['image_order'] = ['property-'.$reordered[0]];
        $this->wire('remove_photo_checkpoint','publisher','PUT',$url,['payload'=>$payload,'expected_revision'=>6,'property_id'=>$id]);
        $input['editor_draft_revision'] = 7;
        $removed = $this->wire('apply_photo_removal','publisher','POST','/api/properties/'.$id,$input);
        $this->check(count($removed->json('data.images')) === 1,'removed_photo_row_absent');
        $this->check(! app(CloudAssetStorageService::class)->existsPrivate($removedPath),'removed_original_cleaned');
        $imageId = (int) $removed->json('data.images.0.id');
        $replacement = (string) Str::uuid();
        $payload['checkpoint_key'] = (string) Str::uuid(); $payload['image_order'] = [$replacement];
        $this->wire('replacement_checkpoint','publisher','PUT',$url,['payload'=>$payload,'expected_revision'=>8,'property_id'=>$id]);
        $this->wire('replacement_image_upload','publisher','POST',$url.'/images/'.$replacement,['expected_revision'=>9],200,$this->syntheticJpeg(8));
        $input['editor_draft_revision'] = 10;
        $replaced = $this->wire('apply_image_replacement','publisher','POST','/api/properties/'.$id,$input);
        $this->check(count($replaced->json('data.images')) === 1 && (int)$replaced->json('data.images.0.id') !== $imageId,'new_replacement_reference');
        $this->wire('replaced_image_reference_inaccessible','publisher','GET','/api/property-media/'.$imageId,[],404);
        $imageId = (int) $replaced->json('data.images.0.id');
        $this->wire('configure_existing_zero_rate_policy','publisher','PUT','/api/properties/'.$id.'/sai',
            ['sai_amount_type'=>'percentage','broker_sai_rate_percent'=>0,'sai_payer'=>'tenant']);
        $this->wire('submit_for_real_review','publisher','POST','/api/properties/'.$id.'/submit');
        $reviewUrl = '/api/admin/listing-review/listings/'.$id;
        $this->wire('regular_cannot_approve','other','POST',$reviewUrl.'/approve',[],403);
        $this->wire('first_reviewer_claim','reviewer','POST',$reviewUrl.'/start');
        $this->wire('second_reviewer_claim_denied','second_reviewer','POST',$reviewUrl.'/start',[],409);
        $this->wire('second_reviewer_read_denied','second_reviewer','GET',$reviewUrl,[],403);
        $this->wire('unreviewed_image_blocks_publish','reviewer','POST',$reviewUrl.'/approve',[],409);
        $review = $this->wire('reviewer_reads_claimed_listing','reviewer','GET',$reviewUrl)->json('data.images.0');
        $decision = ['image_id'=>$imageId,'image_token'=>$review['relevance_token'],'decision'=>'unrelated','reason'=>'Synthetic negative moderation protocol fixture'];
        $this->wire('stale_image_fingerprint_denied','reviewer','POST',$reviewUrl.'/media-review',array_replace($decision,['image_token'=>str_repeat('0',64)]),409);
        $this->wire('negative_image_decision','reviewer','POST',$reviewUrl.'/media-review',$decision);
        $this->wire('unrelated_image_blocks_publish','reviewer','POST',$reviewUrl.'/approve',[],409);
        $this->wire('return_for_correction','reviewer','POST',$reviewUrl.'/return',['reason'=>'Synthetic image correction requested']);
        $this->wire('owner_corrects_returned','publisher','POST','/api/properties/'.$id,['description'=>'تصحيح اصطناعي بعد قرار المراجع']);
        $this->wire('owner_resubmits_same_listing','publisher','POST','/api/properties/'.$id.'/submit');
        $this->wire('reviewer_reclaims','reviewer','POST',$reviewUrl.'/start');
        $this->wire('explicit_positive_image_decision','reviewer','POST',$reviewUrl.'/media-review',array_replace($decision,
            ['decision'=>'relevant','reason'=>'Synthetic affirmative protocol fixture; not a human content acceptance claim']));
        $approved = $this->wire('publish_after_authorized_review','reviewer','POST',$reviewUrl.'/approve',['reason'=>'Synthetic UAT approval; test data only']);
        $this->check($approved->json('data.status') === 'published','published_only_after_review');
        foreach (['search_canonical_arabic'=>'وحدة مكتبية تجريبية','search_common_spelling'=>'وحده مكتبيه تجريبيه',
                  'search_diacritics'=>'وَحدة مَكتبية تَجريبية'] as $case=>$query) {
            $found = $this->wire($case,null,'GET','/api/properties?'.http_build_query(['search'=>$query,'advertiser_id'=>$this->actors['publisher']->id]));
            $this->check(array_column($found->json('data'),'id') === [$id], $case.'_exact_fixture_only');
        }
        $empty = $this->wire('search_true_empty',null,'GET','/api/properties?'.http_build_query(['search'=>'aqer-zero-unrelated-109','advertiser_id'=>$this->actors['publisher']->id]));
        $this->check($empty->json('meta.total') === 0 && $empty->json('data') === [],'zero_results_are_not_an_error');
        $duplicateInput = $input;
        unset($duplicateInput['editor_draft_key'], $duplicateInput['editor_draft_revision']);
        $duplicateInput['title'] = 'نسخة اصطناعية لمحاولة النشر المكرر';
        $duplicate = $this->wire('cross_advertiser_exact_duplicate','other_publisher','POST','/api/properties',$duplicateInput,[201,409],$this->syntheticJpeg(1),'images[0]');
        if ($duplicate->status() === 201) {
            $duplicateId = (int)$duplicate->json('data.id');
            // Review responses expose the physical identity as a nested object;
            // advertiser responses expose its scalar FK. Require a real ID so
            // a missing field can never make two nulls look like a match.
            $approvedAssetId = (int) $approved->json('data.property_asset.id');
            $this->check($approvedAssetId > 0
                && (int) $duplicate->json('data.property_asset_id') === $approvedAssetId,
                'duplicate_same_physical_asset');
            $this->wire('duplicate_has_valid_sai','other_publisher','PUT','/api/properties/'.$duplicateId.'/sai',
                ['sai_amount_type'=>'percentage','broker_sai_rate_percent'=>0,'sai_payer'=>'tenant']);
            $duplicate = $this->wire('duplicate_submission_denied','other_publisher','POST','/api/properties/'.$duplicateId.'/submit',[],409);
        }
        $this->check(str_contains((string)$duplicate->json('message'),'already published'), 'duplicate_denial_is_physical_identity');
        $public = $this->wire('public_sanitized_image',null,'GET','/api/property-media/'.$imageId.'?variant=thumb');
        $this->check(str_starts_with($public->body(),"\xff\xd8") && !str_contains($public->body(),'Exif'), 'published_image_jpeg_no_exif');
        $this->wire('original_still_denied_after_publish',null,'GET','/api/property-media/'.$imageId.'?variant=original',[],422);
        $reportBody = ['target_type'=>'listing','target_id'=>$id,'reason'=>'other','details'=>'Synthetic authorized UAT report; no real complaint'];
        $report = $this->wire('listing_report','other','POST','/api/reports',$reportBody,201);
        $duplicate = $this->wire('report_retry_returns_existing_receipt','other','POST','/api/reports',$reportBody,409);
        $this->check($report->json('data.id') === $duplicate->json('data.id'),'same_report_receipt');
        $case = (int) $report->json('data.id');
        $this->wire('publisher_cannot_read_other_report','publisher','GET','/api/support/cases/'.$case,[],404);
        $this->wire('regular_cannot_review_report','other','GET','/api/admin/support/cases/'.$case,[],403);
        $this->wire('unclaimed_report_review_denied','reviewer','POST','/api/admin/support/cases/'.$case.'/start',[],409);
        $queue = $this->wire('reviewer_reads_report_queue','reviewer','GET','/api/admin/workspace/tasks?scope=inbox&type=report&per_page=100');
        $task = collect($queue->json('data'))->first(fn ($row) => (int)($row['source_id'] ?? 0) === $case && ($row['source_type'] ?? '') === 'report');
        $this->check($task !== null,'report_is_in_shared_queue');
        $this->wire('reviewer_claims_report','reviewer','POST','/api/admin/workspace/tasks/'.(int)$task['id'].'/claim');
        $this->wire('reviewer_starts_report','reviewer','POST','/api/admin/support/cases/'.$case.'/start');
        $this->wire('reviewer_resolves_report','reviewer','PATCH','/api/admin/support/cases/'.$case.'/status',['status'=>'resolved']);
        $resolved = $this->wire('reporter_reads_resolution','other','GET','/api/support/cases/'.$case);
        $this->check($resolved->json('data.status') === 'resolved','report_resolution_roundtrip');
        $thread = (int) $this->wire('property_conversation','other','POST','/api/properties/'.$id.'/conversation',[],201)->json('data.id');
        $this->wire('unrelated_staff_cannot_read_thread','second_reviewer','GET','/api/messages/threads/'.$thread,[],404);
        $message = ['body'=>'Synthetic private message for authorized UAT only','client_message_id'=>(string)Str::uuid()];
        $this->wire('message_before_block','other','POST','/api/messages/threads/'.$thread.'/messages',$message,201);
        $target = $this->actors['publisher']->id;
        $this->wire('account_personal_block','other','PUT','/api/users/'.$target.'/messaging-block');
        $this->wire('sender_block_enforced','other','POST','/api/messages/threads/'.$thread.'/messages',array_replace($message,['client_message_id'=>(string)Str::uuid()]),403);
        $this->wire('recipient_block_enforced','publisher','POST','/api/messages/threads/'.$thread.'/messages',array_replace($message,['client_message_id'=>(string)Str::uuid()]),403);
        $this->wire('new_contact_block_enforced','other','POST','/api/properties/'.$id.'/conversation',[],403);
        $this->wire('history_remains_accessible','other','GET','/api/messages/threads/'.$thread);
        $this->wire('personal_unblock','other','DELETE','/api/users/'.$target.'/messaging-block');
        $this->wire('message_after_unblock','other','POST','/api/messages/threads/'.$thread.'/messages',array_replace($message,['client_message_id'=>(string)Str::uuid()]),201);
        $unusedKey = (string) Str::uuid(); $unusedImageKey = (string) Str::uuid();
        $unusedUrl = '/api/listing-editor-drafts/'.$unusedKey;
        $unusedPayload = ['checkpoint_key'=>(string) Str::uuid(), 'media_version'=>1, 'type'=>'office', 'purpose'=>'rent',
            'image_order'=>[$unusedImageKey], 'fields'=>['title'=>'Synthetic unsubmitted image for erasure']];
        $this->wire('unsubmitted_media_draft_created','publisher','PUT',$unusedUrl,['payload'=>$unusedPayload,'expected_revision'=>0]);
        $this->wire('unsubmitted_media_uploaded','publisher','POST',$unusedUrl.'/images/'.$unusedImageKey,['expected_revision'=>1],200,$this->syntheticJpeg(1));
        $unusedPath = ListingEditorDraft::where('user_id',$target)->where('client_key',$unusedKey)->firstOrFail()->images[$unusedImageKey];
        $this->check(app(CloudAssetStorageService::class)->existsPrivate($unusedPath),'unsubmitted_original_exists_before_erasure');
        $this->wire('staff_cannot_use_consumer_erasure','reviewer','DELETE','/api/account',['confirm_phrase'=>'حذف حسابي نهائيًا'],409);
        $this->wire('deletion_requires_explicit_phrase','publisher','DELETE','/api/account',['confirm_phrase'=>'no'],422);
        $erased = $this->wire('synthetic_publisher_account_erasure','publisher','DELETE','/api/account',['confirm_phrase'=>'حذف حسابي نهائيًا']);
        $this->check($erased->json('data.account_deleted') === true && $erased->json('data.access_revoked') === true,'account_erasure_receipt');
        $this->wire('erased_session_revoked','publisher','GET','/api/auth/me',[],401);
        $this->wire('erased_account_image_unpublished',null,'GET','/api/property-media/'.$imageId.'?variant=thumb',[],404);
        $this->wire('erased_professional_photo_unavailable',null,'GET','/api/advertisers/'.$target.'/photo',[],404);
        $this->check(!app(CloudAssetStorageService::class)->existsPrivate($profilePath),'erased_professional_photo_deleted_from_storage');
        $this->check(!app(CloudAssetStorageService::class)->existsPrivate($unusedPath),'erased_unsubmitted_original_deleted_from_storage');
        foreach (array_keys(config('listing_media.variants')) as $variant) {
            $this->check(!app(CloudAssetStorageService::class)->existsPrivate(app(ListingImageService::class)->variantPath($unusedPath,$variant)),
                'erased_unsubmitted_derivative_'.$variant);
        }
        $this->check(Property::withoutGlobalScopes()->findOrFail($id)->status === 'archived','erasure_archives_listing');
        $this->check(DB::table('listing_reviews')->where('listing_id',$id)->where('action','approved')->exists(),'immutable_review_history_retained');
        $this->check(DB::table('private_messages')->where('thread_id',$thread)->count() === 2,'shared_message_history_retained');
    }

    private function disableFixtures(): bool
    {
        try {
            foreach ($this->actors as $key=>$actor) {
                $this->retireFixture($actor, $this->prefix.$key.'@example.invalid');
            }
            return true;
        } catch (Throwable) {
            return false;
        } finally {
            $this->bearers = [];
        }
    }

    private function retirePreviousSyntheticRun(): void
    {
        // Only actors created by the failed, audited v1 acceptance run. Never
        // accept IDs, emails or storage prefixes from an operator or API caller.
        $prior = AuditLog::where('action','uat.role_journeys.fixture_created')
            ->where('metadata->release_run','2026-10-24-109-v1')->where('subject_type','User')->get();
        if ($prior->count() > 6) throw new RuntimeException('previous_fixture_bound');
        foreach ($prior as $receipt) {
            $key = $receipt->metadata['fixture'] ?? '';
            if (!in_array($key,['publisher','other','other_publisher','reviewer','second_reviewer','manager'],true)) throw new RuntimeException('previous_fixture_key');
            $actor = User::findOrFail($receipt->subject_id);
            $email = 'uat-109-20261024109v1-'.$key.'@example.invalid';
            if ($actor->email !== $email || $actor->account_status !== 'suspended' || $actor->apiTokens()->exists()) throw new RuntimeException('previous_fixture_not_retired');
            $this->retireFixture($actor, $email);
        }
        $this->check(true,'previous_synthetic_run_files_retired');
    }

    private function retireFixture(User $actor, string $expectedEmail): void
    {
        $fresh = $actor->fresh();
        if (!$fresh || ($fresh->account_status !== 'deleted' && $fresh->email !== $expectedEmail)) throw new RuntimeException('fixture_identity_changed');
        $storage = app(CloudAssetStorageService::class);
        $photo = $fresh->public_professional_photo_path;
        $paths = Property::withoutGlobalScopes()->where('user_id',$actor->id)->get()
            ->flatMap(fn ($p) => $p->images()->pluck('path'))->all();
        // Metadata reads are restricted to this newly created synthetic actor.
        // Delete via Storage API, never DELETE storage.objects through SQL.
        if ($storage->cloudEnabled()) {
            $prefix = trim((string)config('services.supabase_storage.private_prefix','private'),'/').'/';
            $objects = DB::table('storage.objects')->where('bucket_id',config('services.supabase_storage.bucket'))
                ->where('name','like',$prefix.'editor-drafts/'.$actor->id.'/%')->limit(101)->pluck('name');
            if ($objects->count() > 100) throw new RuntimeException('synthetic_storage_bound');
            foreach ($objects as $name) $paths[] = substr($name,strlen($prefix));
        }
        $fresh->apiTokens()->delete(); $fresh->roles()->detach();
        $changes = ['public_professional_photo_path'=>null];
        if ($fresh->account_status !== 'deleted') $changes += ['account_status'=>'suspended','phone'=>null,'phone_verified_at'=>null];
        $fresh->forceFill($changes)->save();
        Property::withoutGlobalScopes()->where('user_id',$actor->id)->update(['status'=>'archived','contact_phone'=>null,'contact_whatsapp'=>null]);
        foreach (Property::withoutGlobalScopes()->where('user_id',$actor->id)->get() as $property) $property->images()->delete();
        foreach (ListingEditorDraft::where('user_id',$actor->id)->get() as $draft) {
            $paths = array_merge($paths,array_values($draft->images ?? [])); $draft->delete();
        }
        foreach (array_unique($paths) as $path) {
            app(\App\Services\ListingImageService::class)->removeIfUnused($path);
            if ($storage->existsPrivate($path)) throw new RuntimeException('synthetic_original_cleanup_incomplete');
        }
        if ($photo) {
            app(\App\Services\ProfessionalPhotoService::class)->remove($photo);
            if ($storage->existsPrivate($photo)) throw new RuntimeException('synthetic_photo_cleanup_incomplete');
        }
    }

    private function syntheticJpeg(int $orientation): string
    {
        $image = imagecreatetruecolor(320,160);
        imagefill($image,0,0,imagecolorallocate($image,$orientation === 6 ? 50 : 130,160,190));
        ob_start(); imagejpeg($image,null,90); $jpeg = ob_get_clean(); imagedestroy($image);
        $make = "UAT_PRIVATE_CAMERA\0"; $gpsOffset = 50 + strlen($make);
        $gpsDataOffset = $gpsOffset + 54;
        $tiff = 'II'.pack('vV',42,8).pack('v',3)
            .pack('vvVv',0x112,3,1,$orientation)."\0\0"
            .pack('vvVV',0x10f,2,strlen($make),50)
            .pack('vvVV',0x8825,4,1,$gpsOffset).pack('V',0).$make
            .pack('v',4).pack('vvV',1,2,2)."N\0\0\0"
            .pack('vvVV',2,5,3,$gpsDataOffset)
            .pack('vvV',3,2,2)."E\0\0\0"
            .pack('vvVV',4,5,3,$gpsDataOffset+24).pack('V',0)
            .pack('VVVVVV',15,1,12,1,30,1).pack('VVVVVV',44,1,39,1,15,1);
        $exif = "Exif\0\0".$tiff;
        return substr($jpeg,0,2)."\xff\xe1".pack('n',strlen($exif)+2).$exif.substr($jpeg,2);
    }
}
