<?php

namespace Tests\Feature;

use App\Models\AccountVerificationProfile;
use App\Models\Property;
use App\Models\User;
use App\Models\VerificationChallenge;
use App\Services\AccountErasureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
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
        $roleId=DB::table('roles')->insertGetId([
            'key'=>'support_agent',
            'name_ar'=>'موظف دعم',
            'name_en'=>'Support Agent',
            'is_system'=>true,
            'created_at'=>now(),
            'updated_at'=>now(),
        ]);
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
