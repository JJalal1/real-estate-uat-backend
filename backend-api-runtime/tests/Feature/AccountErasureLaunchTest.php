<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\User;
use App\Models\VerificationChallenge;
use App\Services\AccountErasureService;
use App\Services\ApiTokenService;
use App\Services\ListingImageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use RuntimeException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;
use Tests\TestCase;

class AccountErasureLaunchTest extends TestCase
{
    use RefreshDatabase;

    public function test_service_erases_identity_archives_listing_and_removes_verification_files(): void
    {
        Storage::fake('local');
        $user=$this->user();

        $profile=AccountVerificationProfile::query()->create([
            'user_id'=>$user->id,
            'type'=>AccountVerificationProfile::TYPE_OWNER,
            'status'=>AccountVerificationProfile::STATUS_APPROVED,
            'details'=>['identity'=>'sensitive'],
            'submitted_at'=>now(),
            'reviewed_at'=>now(),
        ]);
        $path='account_verification/'.$user->id.'/identity.jpg';
        Storage::disk('local')->put($path,'private');
        $profile->documents()->create([
            'kind'=>'identity_document',
            'path'=>$path,
            'original_name'=>'id.jpg',
            'mime_type'=>'image/jpeg',
            'size_bytes'=>7,
        ]);

        $property=$this->property($user);
        $oldEmail=$user->email;
        $oldPhone=$user->phone;

        $request=Request::create('/api/account','DELETE');
        $result=app(AccountErasureService::class)->erase($user,$request);

        $fresh=$user->fresh();
        $this->assertTrue($result['account_deleted']);
        $this->assertSame(User::STATUS_DELETED,$fresh->account_status);
        $this->assertSame('مستخدم محذوف',$fresh->name);
        $this->assertNull($fresh->phone);
        $this->assertNull($fresh->phone_verified_at);
        $this->assertNull($fresh->email_verified_at);
        $this->assertStringEndsWith('@deleted.invalid',$fresh->email);
        $this->assertNotSame($oldEmail,$fresh->email);
        $this->assertFalse(User::query()->where('email',$oldEmail)->exists());
        $this->assertFalse(User::query()->where('phone',$oldPhone)->exists());
        $this->assertFalse(Storage::disk('local')->exists($path));
        $this->assertDatabaseMissing('account_verification_profiles',['user_id'=>$user->id]);

        $archived=$property->fresh();
        $this->assertSame('archived',$archived->status);
        $this->assertNull($archived->contact_phone);
        $this->assertNull($archived->contact_whatsapp);
        $this->assertDatabaseHas('audit_logs',[
            'actor_user_id'=>$user->id,
            'action'=>'account.erased',
            'actor_name_snapshot'=>'مستخدم محذوف',
        ]);
    }

    public function test_external_web_flow_requires_verified_session_and_deletes_account(): void
    {
        Storage::fake('local');
        $user=$this->user();

        $this->get('/account-deletion')
            ->assertOk()
            ->assertSee('عقار | Aqer عقارات اليمن')
            ->assertSee('حذف الحساب والبيانات');

        $this->post('/account-deletion/start',['login'=>$user->phone])
            ->assertRedirect()
            ->assertSessionHas('account_deletion_user_id',$user->id)
            ->assertSessionHas('account_deletion_started',true);

        $challenge=VerificationChallenge::query()
            ->where('user_id',$user->id)
            ->where('purpose',VerificationChallenge::PURPOSE_ACCOUNT_DELETION)
            ->latest('id')->firstOrFail();
        $challenge->forceFill(['code_hash'=>Hash::make('123456')])->save();

        $this->post('/account-deletion/confirm',[
            'code'=>'123456',
            'confirm_phrase'=>'حذف حسابي نهائيًا',
        ])->assertRedirect('/account-deletion');

        $this->assertSame(User::STATUS_DELETED,$user->fresh()->account_status);
        $this->get('/account-deletion')
            ->assertOk()
            ->assertSee('تم حذف الحساب ومسح بيانات الهوية الشخصية');
    }

    public function test_erasure_deletes_unused_draft_media_but_preserves_listing_and_other_account_references(): void
    {
        Storage::fake('local');
        $user = $this->user();
        $other = $this->user(['email'=>'other-erasure@example.invalid', 'phone'=>'+967711223345']);
        $token = app(ApiTokenService::class)->issue($user, request())['plain_text_token'];
        $unused = 'editor-drafts/'.$user->id.'/checkpoint/unused.jpg';
        $retained = 'editor-drafts/'.$user->id.'/checkpoint/retained.jpg';
        $foreign = 'editor-drafts/'.$other->id.'/checkpoint/foreign.jpg';
        $this->draft($user, [$unused, $retained]);
        $otherDraft = $this->draft($other, [$foreign]);
        $property = $this->property($user);
        $image = $property->images()->create(['path'=>$retained, 'sort_order'=>0]);
        $images = app(ListingImageService::class);
        foreach ([$unused, $retained, $foreign] as $path) {
            Storage::disk('local')->put($path, 'private original');
            foreach (array_keys(config('listing_media.variants')) as $variant) {
                Storage::disk('local')->put($images->variantPath($path, $variant), 'safe JPEG');
            }
        }

        $this->withToken($token)->deleteJson('/api/account', ['confirm_phrase'=>'حذف حسابي نهائيًا'])
            ->assertOk()->assertJsonPath('data.account_deleted', true)->assertJsonPath('data.access_revoked', true);
        $this->assertDatabaseMissing('listing_editor_drafts', ['user_id'=>$user->id]);
        $this->assertDatabaseHas('listing_editor_drafts', ['id'=>$otherDraft->id]);
        $this->assertDatabaseHas('property_images', ['id'=>$image->id, 'path'=>$retained]);
        $this->assertSame('archived', $property->fresh()->status);
        Storage::disk('local')->assertMissing($unused);
        Storage::disk('local')->assertExists([$retained, $foreign]);
        foreach (array_keys(config('listing_media.variants')) as $variant) {
            Storage::disk('local')->assertMissing($images->variantPath($unused, $variant));
            Storage::disk('local')->assertExists([$images->variantPath($retained, $variant), $images->variantPath($foreign, $variant)]);
        }
        $this->withToken($token)->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_remote_cleanup_failure_rolls_back_erasure_and_preserves_paths_for_an_idempotent_retry(): void
    {
        $user = $this->user();
        $token = app(ApiTokenService::class)->issue($user, request())['plain_text_token'];
        $draft = $this->draft($user, ['editor-drafts/'.$user->id.'/checkpoint/retry.jpg']);
        $property = $this->property($user);
        config(['services.supabase_storage.enabled'=>true, 'services.supabase_storage.url'=>'https://fixture.supabase.co',
            'services.supabase_storage.bucket'=>'fixture', 'services.supabase_storage.server_key'=>'sb_secret_synthetic_only']);
        Http::preventStrayRequests();
        $fail = true;
        Http::fake(['https://fixture.supabase.co/storage/v1/object/fixture'=>function () use (&$fail) {
            return Http::response($fail ? ['message'=>'synthetic unavailable'] : [], $fail ? 503 : 200);
        }]);

        try {
            app(AccountErasureService::class)->erase($user, Request::create('/api/account', 'DELETE'));
            $this->fail('Storage failure must not produce an erasure receipt.');
        } catch (RuntimeException $error) {
            $this->assertStringContainsString('HTTP 503', $error->getMessage());
        }
        $this->assertSame(User::STATUS_ACTIVE, $user->fresh()->account_status);
        $this->assertSame('published', $property->fresh()->status);
        $this->assertDatabaseHas('listing_editor_drafts', ['id'=>$draft->id]);
        $this->assertSame(1, $user->apiTokens()->count());
        $this->withToken($token)->getJson('/api/auth/me')->assertOk();

        $fail = false;
        $result = app(AccountErasureService::class)->erase($user->fresh(), Request::create('/api/account', 'DELETE'));
        $this->assertTrue($result['account_deleted']);
        $this->assertSame(User::STATUS_DELETED, $user->fresh()->account_status);
        $this->assertDatabaseMissing('listing_editor_drafts', ['id'=>$draft->id]);
        $this->assertSame(0, $user->apiTokens()->count());
    }

    public function test_inconsistent_draft_owner_never_deletes_a_foreign_object_or_confirms_erasure(): void
    {
        Storage::fake('local');
        $user = $this->user();
        $foreign = 'editor-drafts/999/checkpoint/foreign.jpg';
        Storage::disk('local')->put($foreign, 'private other account');
        $draft = $this->draft($user, [$foreign]);

        try {
            app(AccountErasureService::class)->erase($user, Request::create('/api/account', 'DELETE'));
            $this->fail('An inconsistent owner must require investigation.');
        } catch (RuntimeException $error) {
            $this->assertStringContainsString('ownership is inconsistent', $error->getMessage());
        }
        Storage::disk('local')->assertExists($foreign);
        $this->assertSame(User::STATUS_ACTIVE, $user->fresh()->account_status);
        $this->assertDatabaseHas('listing_editor_drafts', ['id'=>$draft->id]);
    }

    public function test_external_start_does_not_reveal_whether_account_exists(): void
    {
        $this->post('/account-deletion/start',['login'=>'+967799999999'])
            ->assertRedirect()
            ->assertSessionHas('account_deletion_started',true)
            ->assertSessionMissing('account_deletion_user_id');

        $this->post('/account-deletion/confirm',[
            'code'=>'123456',
            'confirm_phrase'=>'حذف حسابي نهائيًا',
        ])->assertSessionHasErrors('code');
    }

    public function test_staff_account_cannot_use_consumer_erasure_path(): void
    {
        Storage::fake('local');
        $user=$this->user();
        $roleId=(int) DB::table('roles')->where('key','support_agent')->value('id');
        $this->assertGreaterThan(0,$roleId);
        DB::table('user_role')->insert([
            'user_id'=>$user->id,
            'role_id'=>$roleId,
            'assigned_by_user_id'=>null,
            'created_at'=>now(),
        ]);

        $this->expectException(ConflictHttpException::class);
        app(AccountErasureService::class)->erase(
            $user->fresh('roles'),
            Request::create('/api/account','DELETE'),
        );
    }

    public function test_platform_owner_cannot_be_erased(): void
    {
        Storage::fake('local');
        $user=$this->user(['is_platform_owner'=>true]);

        $this->expectException(ConflictHttpException::class);
        app(AccountErasureService::class)->erase(
            $user,
            Request::create('/api/account','DELETE'),
        );
    }

    private function user(array $overrides=[]): User
    {
        return User::query()->create(array_merge([
            'name'=>'مستخدم اختبار الحذف',
            'email'=>'erase-me@example.test',
            'phone'=>'+967711223344',
            'phone_verified_at'=>now(),
            'email_verified_at'=>now(),
            'password'=>Hash::make('StrongPass123!'),
            'account_type'=>User::ACCOUNT_TYPE_REGULAR,
            'account_status'=>User::STATUS_ACTIVE,
            'profile_completed_at'=>now(),
        ],$overrides));
    }

    private function draft(User $user, array $paths): ListingEditorDraft
    {
        return ListingEditorDraft::create([
            'user_id'=>$user->id, 'client_key'=>(string) Str::uuid(), 'revision'=>1,
            'payload'=>['fields'=>['title'=>'Synthetic unsubmitted media']],
            'images'=>array_combine(array_map(fn () => (string) Str::uuid(), $paths), $paths),
        ]);
    }

    private function property(User $user): Property
    {
        return Property::query()->create([
            'user_id'=>$user->id,
            'title'=>'عقار سيؤرشف',
            'description'=>'وصف للاختبار',
            'purpose'=>'sale',
            'type'=>'apartment',
            'price'=>30000000,
            'currency'=>'YER',
            'latitude'=>15.3694,
            'longitude'=>44.1910,
            'address'=>'صنعاء',
            'status'=>'published',
            'review_status'=>'approved',
            'availability_status'=>'available',
            'published_at'=>now(),
            'contact_phone'=>'711223344',
            'contact_whatsapp'=>'711223344',
            'ownership_document_type'=>'purchase_deed',
            'document_owner_name'=>'اسم حساس',
            'owner_relationship_type'=>'owner',
        ]);
    }
}
