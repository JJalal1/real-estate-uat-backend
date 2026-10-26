<?php

namespace App\Console\Commands;

use App\Models\AuditLog;
use App\Console\Support\UatOwnerFixtureRecovery;
use App\Console\Support\UatOwnerRequestRetry;
use App\Models\User;
use App\Models\Role;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use App\Services\UatTestOtpService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use RuntimeException;
use Symfony\Component\Process\Process;

/** Audited, localhost-only preparation. Never publishes plaintext credentials. */
class UatOwnerAcceptancePreflight extends Command
{
    public const RUN='2026-10-26-owner-v2';
    public const ERASURE_PHONE='+12025550149';
    private const ERASURE_EMAIL=UatOwnerFixtureRecovery::EMAIL;
    public const ACTORS=[
        'user'=>['wave3-regular@example.invalid','+12025550102','registered_user'],
        'advertiser'=>['wave3-owner@example.invalid','+12025550101','registered_user'],
        'broker'=>['wave3-strong@example.invalid','+12025550104','broker'],
        'reviewer'=>['uat-support-agent-1@example.invalid','+12025550106','support_agent'],
        'support'=>['uat-support-manager@example.invalid','+12025550108','support_manager'],
        'admin'=>['uat-general-manager@example.invalid','+12025550109','super_admin'],
    ];
    protected $signature='uat:owner-acceptance-preflight {--run=} {--base-url=}';
    protected $description='Precheck existing fictional UAT actors and create bounded owner-only acceptance fixtures';
    private array $receipts=[];
    private array $tokens=[];
    private array $users=[];
    private string $base;
    private float $started;

    public function handle(): int
    {
        $this->base=rtrim((string)$this->option('base-url'),'/');
        if (!app()->environment('staging') || $this->option('run')!==self::RUN || env('UAT_OWNER_ACCEPTANCE_RUN')!==self::RUN
            || !filter_var(env('UAT_OWNER_ACCEPTANCE_FIXTURES_ENABLED',false),FILTER_VALIDATE_BOOLEAN)
            || !preg_match('#^http://127\.0\.0\.1:[0-9]{2,5}$#D',$this->base)
            || parse_url((string)config('services.supabase_storage.url'),PHP_URL_HOST)!=='ipxsgxsqzthpgthwvdno.supabase.co'
            || !app(CloudAssetStorageService::class)->cloudEnabled()) {
            $this->line('AQER_OWNER_PREFLIGHT {"status":"guard-refused","writes":false}');return self::FAILURE;
        }
        $this->started=microtime(true);
        $accounts=[];$actors=self::ACTORS;$erasure=null;
        try {
            foreach (self::ACTORS as $key=>[$email,$phone,$role]) {
                $user=User::where('email',$email)->where('phone',$phone)->first();
                if (!$user || !$user->isActive() || !$user->profile_completed_at || !$user->roles()->where('key',$role)->exists()) throw new RuntimeException('fixture_actor_not_ready');
                if (in_array($key,['advertiser','broker'],true) && !$user->hasApprovedVerificationProfile()) throw new RuntimeException('fixture_profile_not_ready');
                $code=app(UatTestOtpService::class)->codeFor($phone);
                if ($code===null) throw new RuntimeException('fixture_otp_not_allowlisted');
                $this->users[$key]=$user;
                // This array is encrypted directly; never logged or put in a URL.
                $accounts[$key]=['phone'=>$phone,'test_otp'=>$code,'user_id'=>$user->id];
            }
            if (app(UatTestOtpService::class)->codeFor(self::ERASURE_PHONE)===null) throw new RuntimeException('fixture_otp_not_allowlisted');
            $erasure=app(UatOwnerFixtureRecovery::class)->find();
            if (!Role::where('key','registered_user')->exists()) throw new RuntimeException('fixture_role_missing');
            $recipient=resource_path('uat-owner-recipient.pem');
            if (!is_file($recipient) || !hash_equals('12f6a686d39cef1b63f90011b979ebaef0a25f431d9f4eb1aa4d114a19c0f5e2',hash_file('sha256',$recipient))) throw new RuntimeException('approved_recipient_missing');
        } catch (\Throwable $error) {
            $this->line('AQER_OWNER_PREFLIGHT '.json_encode(['status'=>'precondition-blocked','writes'=>false,'reason'=>in_array($error->getMessage(),['fixture_actor_not_ready','fixture_profile_not_ready','fixture_otp_not_allowlisted','approved_recipient_missing','fixture_collision','fixture_role_missing'],true)?$error->getMessage():class_basename($error)]));
            return self::FAILURE;
        }
        $fresh=DB::transaction(function (): bool {
            DB::select('select pg_advisory_xact_lock(149,20261026)');
            if (AuditLog::where('action','uat.owner_acceptance.started')->where('metadata->release_run',self::RUN)->exists()) return false;
            app(AuditLogService::class)->record(null,'uat.owner_acceptance.started',null,['release_run'=>self::RUN]);return true;
        });
        if (!$fresh) { $this->line('AQER_OWNER_PREFLIGHT {"status":"already-started-no-replay"}');return self::FAILURE; }
        $manifest=['run'=>self::RUN,'backend_sha'=>env('RENDER_GIT_COMMIT'),'fixture_only'=>true,'property_ids'=>[60,61,62],'created_at'=>now()->toIso8601String()];
        $passed=false;
        try {
            // This fresh account has no historical financial/shared records. Keep
            // it intact for the owner's explicit account-erasure acceptance.
            $consumer=$erasure ?? User::create(['name'=>UatOwnerFixtureRecovery::NAME,'email'=>self::ERASURE_EMAIL,
                'phone'=>self::ERASURE_PHONE,'password'=>Str::random(96),'phone_verified_at'=>now(),
                'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active','account_type'=>'regular']);
            if ($erasure===null) $consumer->roles()->sync([Role::where('key','registered_user')->value('id')=>['created_at'=>now()]]);
            $this->users['erasure']=$consumer;
            $actors['erasure']=[self::ERASURE_EMAIL,self::ERASURE_PHONE,'registered_user'];
            $accounts['erasure']=['phone'=>self::ERASURE_PHONE,'test_otp'=>app(UatTestOtpService::class)->codeFor(self::ERASURE_PHONE),'user_id'=>$consumer->id];
            app(AuditLogService::class)->record(null,$erasure===null?'uat.owner_acceptance.fixture_created':'uat.owner_acceptance.fixture_recovered',$consumer,
                ['release_run'=>self::RUN,'fixture'=>'erasure','previous_run'=>$erasure===null?null:UatOwnerFixtureRecovery::PREVIOUS]);
            $manifest['owner_erasure_user_id']=$consumer->id;
            foreach ($actors as $key=>[, $phone]) {
                $this->wire('otp_start_'.$key,null,'POST','/api/auth/whatsapp/start',['phone'=>$phone,'intent'=>'login']);
                $login=$this->wire('otp_login_'.$key,null,'POST','/api/auth/whatsapp/verify',['phone'=>$phone,'code'=>$accounts[$key]['test_otp']]);
                $token=$login->json('data.token');
                if (!is_string($token) || $token==='' || (int)$login->json('data.user.id')!==$this->users[$key]->id) throw new RuntimeException('login_identity_mismatch');
                $this->tokens[$key]=$token;
                $this->wire('current_actor_'.$key,$key,'GET','/api/auth/me');
            }
            foreach (['user'=>['/api/favorites','/api/saved-searches','/api/messages/threads'],
                'advertiser'=>['/api/properties/mine/list'],'broker'=>['/api/properties/mine/list','/api/listing-editor-drafts'],
                'reviewer'=>['/api/admin/workspace/tasks?scope=inbox'],
                'support'=>['/api/admin/workspace/dashboard'],'admin'=>['/api/admin/dashboard','/api/admin/access/catalog']] as $key=>$paths) {
                foreach ($paths as $index=>$path) $this->wire('role_read_'.$key.'_'.$index,$key,'GET',$path);
            }
            $this->wire('regular_admin_rejected','user','GET','/api/admin/dashboard',[],403);
            // Independent draft remains for restart/recovery acceptance.
            $draft=(string)Str::uuid();$image=(string)Str::uuid();
            $payload=['checkpoint_key'=>(string)Str::uuid(),'media_version'=>1,'type'=>'office','purpose'=>'rent',
                'latitude'=>15.123456,'longitude'=>44.654321,'image_order'=>[$image],
                'fields'=>['title'=>'اختبار المالك — مسودة استعادة','area'=>'65']];
            $url='/api/listing-editor-drafts/'.$draft;
            $this->wire('owner_recovery_draft','broker','PUT',$url,['payload'=>$payload,'expected_revision'=>0]);
            $photo=file_get_contents(resource_path('uat-wave3/images/office.jpg'));
            if (!is_string($photo)) throw new RuntimeException('synthetic_photo_missing');
            $this->wire('owner_recovery_photo','broker','POST',$url.'/images/'.$image,['expected_revision'=>1],200,$photo);
            $this->wire('foreign_draft_rejected','user','GET',$url,[],404);
            $this->wire('recovery_draft_readback','broker','GET',$url);
            $manifest['recovery_draft_key']=$draft;
            // Separate pending review: one property photograph and one explicitly unrelated image.
            $draft=(string)Str::uuid();$first=(string)Str::uuid();$second=(string)Str::uuid();
            $payload['checkpoint_key']=(string)Str::uuid();$payload['fields']['title']='اختبار المالك — مراجعة الصور';$payload['image_order']=[$first,$second];
            $url='/api/listing-editor-drafts/'.$draft;
            $this->wire('owner_review_draft','broker','PUT',$url,['payload'=>$payload,'expected_revision'=>0]);
            $this->wire('owner_relevant_photo','broker','POST',$url.'/images/'.$first,['expected_revision'=>1],200,$photo);
            $canvas=imagecreatetruecolor(720,480);imagefill($canvas,0,0,0xffdd88);
            imagestring($canvas,5,30,200,'SYNTHETIC TEST PATTERN - NOT A PROPERTY PHOTO',0x223344);
            ob_start();imagejpeg($canvas,null,85);$unrelated=ob_get_clean();imagedestroy($canvas);unset($canvas);
            $this->wire('owner_unrelated_photo','broker','POST',$url.'/images/'.$second,['expected_revision'=>2],200,$unrelated);
            $input=['listing_input_version'=>9,'title'=>'اختبار المالك — مراجعة الصور '.self::RUN,'description'=>'عقار اصطناعي لا يمثل إعلانًا تجاريًا حقيقيًا.',
                'type'=>'office','purpose'=>'rent','price'=>75000,'monthly_rent'=>75000,'currency'=>'YER','area_value'=>65,'area_unit'=>'sqm',
                'floor_number'=>'0','has_parking'=>0,'building_facade'=>'north','address'=>'صنعاء موقع اصطناعي لاختبار المالك '.self::RUN,
                'building_reference'=>'owner-acceptance-'.self::RUN,'unit_number'=>'owner-149','contact_phone'=>'700000000','contact_whatsapp'=>'700000000',
                'latitude'=>15.123456,'longitude'=>44.654321,'editor_draft_key'=>$draft,'editor_draft_revision'=>3];
            $created=$this->wire('owner_review_listing','broker','POST','/api/properties',$input,201);
            $listing=(int)$created->json('data.id');if ($listing<=0) throw new RuntimeException('fixture_listing_missing');
            $this->wire('owner_review_sai','broker','PUT','/api/properties/'.$listing.'/sai',
                ['sai_amount_type'=>'percentage','broker_sai_rate_percent'=>0,'sai_payer'=>'tenant']);
            $this->wire('owner_review_submit','broker','POST','/api/properties/'.$listing.'/submit');
            $this->wire('unreviewed_owner_listing_not_public',null,'GET','/api/properties/'.$listing,[],404);
            $evidence=$this->wire('reviewer_can_open_owner_evidence','reviewer','GET','/api/admin/listing-review/listings/'.$listing);
            $images=$evidence->json('data.images');
            if ((int)$evidence->json('data.id')!==$listing || $evidence->json('data.review_status')!=='submitted'
                || !is_array($images) || count($images)!==2) throw new RuntimeException('fixture_review_not_ready');
            $manifest['review_listing_id']=$listing;
            $manifest['review_image_ids']=array_map(fn ($image)=>(int)$image['id'],$images);
            foreach ([60,61,62] as $id) {
                $this->wire('public_fixture_'.$id,null,'GET','/api/properties/'.$id);
                $this->wire('external_share_fixture_'.$id,null,'GET','/l/properties/'.$id);
            }
            $process=new Process(['openssl','cms','-encrypt','-binary','-aes-256-gcm','-outform','DER','-recip',$recipient,
                '-keyopt','rsa_padding_mode:oaep','-keyopt','rsa_oaep_md:sha256']);
            $process->setInput(json_encode(['manifest'=>$manifest,'accounts'=>$accounts],JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE));
            $process->setTimeout(15);$process->mustRun();$cipher=$process->getOutput();
            if (strlen($cipher)<128 || strlen($cipher)>65536 || $cipher[0]!=="\x30") throw new RuntimeException('capsule_unavailable');
            $manifest['access_capsule_cms_base64_parts']=str_split(base64_encode($cipher),768);
            $manifest['access_capsule_sha256']=hash('sha256',$cipher);
            $passed=true;
        } catch (\Throwable $error) {
            // Keep incomplete setup visible; no success, arbitrary cleanup or replay.
            $manifest['failure_class']=class_basename($error);
        } finally {
            $revoked=true;
            foreach ($this->tokens as $key=>$plain) {
                $count=$this->users[$key]->apiTokens()->where('token_hash',hash('sha256',$plain))->delete();
                if ($count!==1) $revoked=false;
            }
            $manifest+=['status'=>$passed && $revoked?'passed':'incomplete','probe_sessions_revoked'=>$revoked,
                'cases'=>$this->receipts,'elapsed_ms'=>round((microtime(true)-$this->started)*1000),
                'handset_acceptance'=>false,'fixtures_retained_for_owner'=>true];
            app(AuditLogService::class)->record(null,'uat.owner_acceptance.finished',null,['release_run'=>self::RUN,'result'=>$manifest]);
            $this->line('AQER_OWNER_PREFLIGHT '.json_encode($manifest,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
        }
        return $passed && $revoked?self::SUCCESS:self::FAILURE;
    }

    private function wire(string $name,?string $actor,string $method,string $path,array $data=[],int $expected=200,?string $image=null): \Illuminate\Http\Client\Response
    {
        if ((!str_starts_with($path,'/api/') && !preg_match('#^/l/properties/[0-9]+$#D',$path)) || str_contains($path,'..')
            || count($this->receipts)>=65 || microtime(true)-$this->started>480) throw new RuntimeException('probe_bound');
        DB::disconnect();
        $request=Http::acceptJson()->withUserAgent('Aqer-Owner-Acceptance/1.0')->connectTimeout(5)->timeout(40)->withoutRedirecting();
        if ($actor!==null) $request->withToken($this->tokens[$actor]);
        if ($image!==null) $request->attach('image',$image,'synthetic.jpg',['Content-Type'=>'image/jpeg']);
        $send=function () use ($image,$request,$path,$data,$method) {
            if (count($this->receipts)>=65 || microtime(true)-$this->started>480) throw new RuntimeException('probe_bound');
            return $image!==null?$request->post($this->base.$path,$data):$request->send($method,$this->base.$path,$method==='GET'?[]:['json'=>$data]);
        };
        $response=app(UatOwnerRequestRetry::class)->send($path,$send,function (int $seconds,int $attempt) use ($name): void {
            $this->receipts[]=['case'=>$name.'_throttled_'.$attempt,'status'=>429,'expected'=>429,'passed'=>true,'wait_seconds'=>$seconds];
        },$this->started);
        $okay=$response->status()===$expected;
        $this->receipts[]=['case'=>$name,'status'=>$response->status(),'expected'=>$expected,'passed'=>$okay,
            'validation_fields'=>$okay?[]:array_keys((array)$response->json('errors',[]))];
        if (!$okay) throw new RuntimeException('fixture_request_failed');
        return $response;
    }
}
