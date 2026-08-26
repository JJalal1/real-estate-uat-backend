<?php
namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class Stage6IdentityApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_verify_create_listing_and_logout(): void
    {
        $register = $this->postJson('/api/auth/register', [
            'name'=>'Stage Six User','email'=>'stage6@example.test','phone'=>'+967700000101',
            'password'=>'StrongPass123!','password_confirmation'=>'StrongPass123!',
        ]);
        $register->assertCreated()->assertJsonPath('data.user.account_status','pending_verification');
        $token=(string)$register->json('data.token');
        $headers=$this->bearer($token);

        $this->withHeaders($headers)->postJson('/api/properties',$this->listingPayload())
            ->assertForbidden()->assertJsonPath('code','ACCOUNT_NOT_ACTIVE');

        $codeResponse=$this->withHeaders($headers)->postJson('/api/auth/phone/request');
        $codeResponse->assertOk();
        $code=(string)$codeResponse->json('data.debug_code');
        $this->assertMatchesRegularExpression('/^\d{6}$/',$code);

        $this->withHeaders($headers)->postJson('/api/auth/phone/verify',['code'=>$code])
            ->assertOk()->assertJsonPath('data.user.account_status','active');

        $created=$this->withHeaders($headers)->postJson('/api/properties',$this->listingPayload());
        $created->assertCreated()->assertJsonPath('data.status','draft')->assertJsonPath('data.review_status','draft');
        $id=(int)$created->json('data.id');

        $this->withHeaders($headers)->getJson('/api/properties/mine/list')
            ->assertOk()->assertJsonPath('data.0.id',$id);

        $this->withHeaders($headers)->postJson('/api/auth/logout')->assertOk();
        $this->withHeaders($headers)->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_phone_normalization_accepts_rtl_marks_spacing_and_arabic_digits(): void
    {
        $withBidiMarks = "\u{200F}+\u{200E}967 777-838-3574";
        $register = $this->postJson('/api/auth/register', [
            'name'=>'RTL Phone User','email'=>'rtl-phone@example.test','phone'=>$withBidiMarks,
            'password'=>'StrongPass123!','password_confirmation'=>'StrongPass123!',
        ]);
        $register->assertCreated()->assertJsonPath('data.user.phone','+9677778383574');

        $arabicDigits = $this->postJson('/api/auth/register', [
            'name'=>'Arabic Digits User','email'=>'arabic-phone@example.test','phone'=>'+٩٦٧٧٧٧٨٣٨٣٥٧٥',
            'password'=>'StrongPass123!','password_confirmation'=>'StrongPass123!',
        ]);
        $arabicDigits->assertCreated()->assertJsonPath('data.user.phone','+9677778383575');
    }

    public function test_legacy_owner_key_claim_moves_stage5_listings(): void
    {
        $demo=User::query()->create([
            'name'=>'Stage 5 Device Listings','email'=>'stage5-owner@local.invalid',
            'password'=>Hash::make('not-used'),'account_status'=>User::STATUS_ACTIVE,
        ]);
        $key='stage5-test-owner-key-00000000000000000999';
        $property=Property::query()->create(array_merge($this->listingPayload(),[
            'user_id'=>$demo->id,'owner_key'=>$key,'status'=>'published',
        ]));

        $register=$this->postJson('/api/auth/register',[
            'name'=>'Legacy Owner','email'=>'legacy@example.test','phone'=>'+967700000102',
            'password'=>'StrongPass123!','password_confirmation'=>'StrongPass123!',
            'legacy_owner_key'=>$key,
        ]);
        $register->assertCreated()->assertJsonPath('data.legacy_listings_claimed',1);
        $newId=(int)$register->json('data.user.id');

        $this->assertDatabaseHas('properties',[
            'id'=>$property->id,'user_id'=>$newId,'owner_key'=>null,
        ]);

        $this->withHeader('X-Owner-Key',$key)
            ->deleteJson('/api/properties/'.$property->id)->assertUnauthorized();
    }

    public function test_user_cannot_modify_another_users_listing(): void
    {
        [$owner,$ownerHeaders]=$this->verifiedUser('owner@example.test','+967700000103');
        [, $otherHeaders]=$this->verifiedUser('other@example.test','+967700000104');
        $property=Property::query()->create(array_merge($this->listingPayload(),[
            'user_id'=>$owner->id,'owner_key'=>null,'status'=>'published',
        ]));
        $this->withHeaders($otherHeaders)->postJson('/api/properties/'.$property->id,['title'=>'Forbidden'])->assertForbidden();
        $this->withHeaders($otherHeaders)->deleteJson('/api/properties/'.$property->id)->assertForbidden();
    }

    public function test_password_reset_revokes_existing_tokens(): void
    {
        [, $headers]=$this->verifiedUser('recovery@example.test','+967700000105');
        $forgot=$this->postJson('/api/auth/password/forgot',['login'=>'recovery@example.test']);
        $forgot->assertOk();
        $code=(string)$forgot->json('data.debug_code');

        $this->postJson('/api/auth/password/reset',[
            'login'=>'recovery@example.test','code'=>$code,
            'password'=>'NewStrongPass123!','password_confirmation'=>'NewStrongPass123!',
        ])->assertOk();

        $this->withHeaders($headers)->getJson('/api/auth/me')->assertUnauthorized();
        $this->postJson('/api/auth/login',[
            'login'=>'recovery@example.test','password'=>'NewStrongPass123!',
        ])->assertOk();
    }

    public function test_suspended_and_banned_accounts_are_rejected(): void
    {
        [$user,$headers]=$this->verifiedUser('status@example.test','+967700000106');
        $user->forceFill(['account_status'=>User::STATUS_SUSPENDED])->save();
        $this->withHeaders($headers)->getJson('/api/auth/me')->assertForbidden();

        $user->forceFill(['account_status'=>User::STATUS_BANNED])->save();
        $this->postJson('/api/auth/login',[
            'login'=>'status@example.test','password'=>'StrongPass123!',
        ])->assertForbidden();
    }

    private function verifiedUser(string $email,string $phone): array
    {
        $register=$this->postJson('/api/auth/register',[
            'name'=>'Verified User','email'=>$email,'phone'=>$phone,
            'password'=>'StrongPass123!','password_confirmation'=>'StrongPass123!',
        ]);
        $token=(string)$register->json('data.token');
        $headers=$this->bearer($token);
        $code=(string)$this->withHeaders($headers)->postJson('/api/auth/phone/request')->json('data.debug_code');
        $this->withHeaders($headers)->postJson('/api/auth/phone/verify',['code'=>$code])->assertOk();
        return [User::query()->where('email',$email)->firstOrFail(),$headers];
    }

    private function bearer(string $token): array
    {
        return ['Authorization'=>'Bearer '.$token,'Accept'=>'application/json'];
    }

    private function listingPayload(): array
    {
        return [
            'title'=>'Stage 6 listing','description'=>'Identity regression listing',
            'purpose'=>'sale','type'=>'house','price'=>50000000,'currency'=>'YER',
            'area_m2'=>220,'bedrooms'=>4,'bathrooms'=>3,'address'=>'Sanaa',
            'latitude'=>15.3694,'longitude'=>44.1910,
            'contact_phone'=>'+967700000000','contact_whatsapp'=>'+967700000000',
        ];
    }
}
