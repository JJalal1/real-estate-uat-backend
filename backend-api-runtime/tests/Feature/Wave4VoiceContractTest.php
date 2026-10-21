<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class Wave4VoiceContractTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp(); Cache::flush();
        config(['gemini.enabled'=>true,'gemini.key'=>'fixture-server-key','gemini.model'=>'gemini-3.1-flash-lite','gemini.daily_limit'=>200]);
        Http::preventStrayRequests();
    }

    private function response(array $value, string $finish='STOP'): array
    {
        return ['candidates'=>[['finishReason'=>$finish,'content'=>['parts'=>[['text'=>json_encode($value,JSON_UNESCAPED_UNICODE)]]]]]];
    }

    private function audio(): UploadedFile
    {
        // A small M4A container fixture; no real person's voice is stored in tests.
        $bytes=pack('N',24).'ftypM4A '.pack('N',0).'M4A mp42'.pack('N',520).'mdat'.str_repeat("\0",512);
        return UploadedFile::fake()->createWithContent('whole-recording.m4a',$bytes);
    }

    public function test_transcription_uses_the_complete_clip_then_a_followup_preserves_the_existing_search_context(): void
    {
        $audio=$this->audio(); $bytes=file_get_contents($audio->getRealPath());
        $transcript=str_repeat('أحتاج أن أفكر في هذا الطلب قليلًا. ',65).'خلي السعر بين خمسين ومئة ألف';
        $this->assertGreaterThan(1500,mb_strlen($transcript));
        Http::fake(['generativelanguage.googleapis.com/*'=>function ($request) use ($bytes,$transcript) {
            $this->assertTrue($request->hasHeader('x-goog-api-key','fixture-server-key'));
            $this->assertArrayNotHasKey('tools',$request->data());
            $parts=$request['contents'][0]['parts'];
            if (isset($parts[1]['inlineData'])) {
                $this->assertSame($bytes,base64_decode($parts[1]['inlineData']['data'],true));
                $this->assertSame('audio/mp4',$parts[1]['inlineData']['mimeType']);
                return Http::response($this->response(['transcript'=>$transcript]));
            }
            $input=json_decode($parts[0]['text'],true);
            $this->assertSame($transcript,$input['follow_up']);
            $this->assertSame('صنعاء',$input['current_filters']['search']);
            return Http::response($this->response(['set'=>['min_price'=>50000,'max_price'=>100000],'remove'=>[]]));
        }]);
        $r=$this->post('/api/ai/transcribe',['audio'=>$audio],['Accept'=>'application/json'])->assertOk()
            ->assertJsonPath('data.transcript',$transcript)->assertJsonPath('data.complete',true);
        $this->assertStringContainsString('no-store',(string)$r->headers->get('Cache-Control'));
        $this->assertDatabaseCount('properties',0);
        $this->postJson('/api/ai/search',['message'=>$r->json('data.transcript'),'revision'=>7,
            'filters'=>['type'=>'apartment','purpose'=>'rent','search'=>'صنعاء','min_bedrooms'=>3]])->assertOk()
            ->assertJsonPath('data.revision',7)->assertJsonPath('data.filters.type','apartment')->assertJsonPath('data.filters.purpose','rent')
            ->assertJsonPath('data.filters.search','صنعاء')->assertJsonPath('data.filters.min_bedrooms',3)
            ->assertJsonPath('data.filters.min_price',50000)->assertJsonPath('data.filters.max_price',100000);
        Http::assertSentCount(2);
        $this->assertDatabaseCount('message_threads',0);
    }

    public function test_invalid_audio_is_rejected_before_a_provider_request(): void
    {
        $this->post('/api/ai/transcribe',['audio'=>UploadedFile::fake()->createWithContent('speech.m4a','not a recording')],['Accept'=>'application/json'])->assertUnprocessable();
        $this->post('/api/ai/transcribe',['audio'=>UploadedFile::fake()->create('large.m4a',8193,'audio/mp4')],['Accept'=>'application/json'])->assertUnprocessable();
        Http::assertNothingSent();
    }

    public function test_truncated_or_unexpected_model_output_cannot_be_executed_as_a_partial_transcript(): void
    {
        Http::fake(['generativelanguage.googleapis.com/*'=>Http::sequence()
            ->push($this->response(['transcript'=>'جزء ناقص من الكلام'],'MAX_TOKENS'))
            ->push($this->response(['transcript'=>'نص','action'=>'reset_search']))]);
        foreach ([0,1] as $_) {
            $this->post('/api/ai/transcribe',['audio'=>$this->audio()],['Accept'=>'application/json'])->assertStatus(503)
                ->assertJsonPath('code','ai_unavailable')->assertJsonMissingPath('data.transcript');
        }
        $this->assertDatabaseCount('properties',0);
        Http::assertSentCount(2);
    }

    public function test_selected_conditions_can_only_be_reordered_for_review_and_never_mutate_a_listing(): void
    {
        $user=User::create(['name'=>'معلن اختبار','email'=>'conditions@wave4-ai.example.test','phone'=>'+967770043001','password'=>Hash::make('fixture-only'),
            'phone_verified_at'=>now(),'profile_completed_at'=>now(),'identity_policy_version'=>2,'account_status'=>'active']);
        $user->roles()->sync([Role::where('key','registered_user')->firstOrFail()->id=>['created_at'=>now()]]);
        AccountVerificationProfile::create(['user_id'=>$user->id,'type'=>'broker','status'=>'approved','reviewed_at'=>now()]);
        $token='conditions-fixture'; $user->apiTokens()->create(['name'=>'fixture','token_hash'=>hash('sha256',$token),'token_prefix'=>substr($token,0,12),'expires_at'=>now()->addHour()]);
        $headers=['Authorization'=>'Bearer '.$token,'Accept'=>'application/json'];
        $conditions=[['kind'=>'advance','months'=>2],['kind'=>'special','text'=>'لا يسمح بالتأجير من الباطن']];
        Http::fake(['generativelanguage.googleapis.com/*'=>Http::sequence()->push($this->response(['order'=>[1,0]]))->push($this->response(['order'=>[0,0]]))]);
        $this->withHeaders($headers)->postJson('/api/ai/rental-conditions',['rental_conditions'=>$conditions])->assertStatus(410)
            ->assertJsonPath('code','RENTAL_CONDITIONS_AI_RETIRED');
        $foreign=Property::create(['user_id'=>User::factory()->create()->id,'title'=>'Private draft','purpose'=>'sale','type'=>'house',
            'price'=>100000,'currency'=>'YER','latitude'=>15.4,'longitude'=>44.2,'status'=>'draft','review_status'=>'draft']);
        $this->withHeaders($headers)->postJson('/api/ai/rental-conditions',['property_id'=>$foreign->id,'rental_conditions'=>$conditions])->assertNotFound();
        Http::assertNothingSent();
        $this->assertDatabaseCount('properties',1);
        $this->assertDatabaseCount('property_sai_terms',0);
    }
}
