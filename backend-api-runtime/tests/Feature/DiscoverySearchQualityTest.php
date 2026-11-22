<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class DiscoverySearchQualityTest extends TestCase
{
    use RefreshDatabase;

    public function test_arabic_search_normalizes_alef_diacritics_and_matches_tokens_across_fields(): void
    {
        $owner = $this->owner();

        $match = $this->listing($owner, [
            'title' => 'شَقَّة عائلية',
            'description' => 'سكن هادئ',
            'address' => 'صنعاء، حَدَّة',
        ]);
        $this->listing($owner, [
            'title' => 'فيلا مستقلة',
            'description' => 'في منطقة أخرى',
            'address' => 'تعز',
        ]);

        $this->getJson('/api/properties?search=شقه%20حده')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $match->id);

        $this->getJson('/api/properties?search=شقة%20حدة')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $match->id);

        $ibb = $this->listing($owner, [
            'title' => 'أرض في إب',
            'description' => 'فرصة استثمارية',
            'address' => 'إب',
        ]);

        $this->getJson('/api/properties?search=ارض%20اب')
            ->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.id', $ibb->id);
    }

    public function test_exact_normalized_title_ranks_before_newer_description_match(): void
    {
        $owner = $this->owner();

        $exact = $this->listing($owner, [
            'title' => 'إب',
            'description' => 'عقار في وسط المدينة',
            'address' => 'اليمن',
        ]);
        $this->listing($owner, [
            'title' => 'عرض أحدث',
            'description' => 'عقار مميز في إب',
            'address' => 'اليمن',
        ]);

        $this->getJson('/api/properties?search=اب&sort=latest')
            ->assertOk()
            ->assertJsonPath('meta.total', 2)
            ->assertJsonPath('data.0.id', $exact->id);
    }

    public function test_common_taa_haa_spelling_keeps_scope_negative_results_and_stored_facts(): void
    {
        $owner = $this->owner();
        $match = $this->listing($owner,['title'=>'وحدة مكتبية تجريبية','address'=>'صنعاء حدة']);
        $hidden = $this->listing($owner,['title'=>'وحده مكتبيه تجريبيه','status'=>'draft','review_status'=>'draft']);
        $other = $this->listing($owner,['title'=>'فيلا مستقلة','address'=>'تعز']);
        foreach (['وحدة مكتبية تجريبية','وحده مكتبيه تجريبيه','وَحدة مَكتبية تَجريبية'] as $query) {
            $this->getJson('/api/properties?'.http_build_query(['search'=>$query,'advertiser_id'=>$owner->id]))
                ->assertOk()->assertJsonPath('meta.total',1)->assertJsonPath('data.0.id',$match->id);
        }
        $this->getJson('/api/properties?'.http_build_query(['search'=>'وحده جغرافية غير موجودة']))
            ->assertOk()->assertJsonPath('meta.total',0);
        $this->getJson('/api/properties?'.http_build_query(['search'=>'وحده مكتبيه','currency'=>'USD']))
            ->assertOk()->assertJsonPath('meta.total',0);
        $this->assertSame('وحدة مكتبية تجريبية',$match->fresh()->title);
        $this->assertSame('draft',$hidden->fresh()->status);
        $this->assertSame('فيلا مستقلة',$other->fresh()->title);
    }

    public function test_marketplace_loads_photos_once_for_listings_in_multiple_sections(): void
    {
        $owner = $this->owner();
        $sale = $this->listing($owner, ['latitude' => 15.3700]);
        $sale->forceFill(['spotlight_until' => now()->addDay()])->save();
        $rent = $this->listing($owner, ['purpose' => 'rent', 'monthly_rent' => 100000]);
        $sale->images()->createMany([
            ['path' => 'test/gallery.jpg', 'cdn_url' => 'https://example.test/gallery.jpg', 'sort_order' => 0, 'is_primary' => false],
            ['path' => 'test/cover.jpg', 'cdn_url' => 'https://example.test/cover.jpg', 'sort_order' => 1, 'is_primary' => true],
        ]);
        $rent->images()->create([
            'path' => 'test/rent.jpg',
            'cdn_url' => 'https://example.test/rent.jpg',
            'sort_order' => 0,
            'is_primary' => true,
        ]);

        $connection = DB::connection();
        if ($connection->getDriverName() === 'pgsql') {
            $connection->table('properties')->whereIn('id', [$sale->id, $rent->id])->update([
                'location' => DB::raw('ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography'),
            ]);
        }

        $connection->flushQueryLog();
        $connection->enableQueryLog();
        try {
            $response = $this->getJson('/api/marketplace?latitude=15.3694&longitude=44.191&accuracy_m=5');
            $queries = $connection->getQueryLog();
        } finally {
            $connection->disableQueryLog();
            $connection->flushQueryLog();
        }

        $response->assertOk()
            ->assertJsonPath('data.context.governorate_code', 'AMANAT_AL_ASIMAH')
            ->assertJsonPath('data.section_order', ['nearby', 'spotlight', 'latest', 'sale', 'rent']);
        $sections = $response->json('data.sections');
        $this->assertSame([$rent->id, $sale->id], array_column($sections['nearby'], 'id'));
        $this->assertSame([$rent->id, $sale->id], array_column($sections['latest'], 'id'));
        $this->assertSame([$sale->id], array_column($sections['sale'], 'id'));
        $this->assertSame([$rent->id], array_column($sections['rent'], 'id'));
        $this->assertSame($sections['sale'][0], $sections['spotlight'][0]);
        $this->assertSame($sections['sale'][0], $sections['latest'][1]);
        $this->assertSame($sections['sale'][0], $sections['nearby'][1]);
        $this->assertSame('https://example.test/cover.jpg', $sections['sale'][0]['main_image']);
        $this->assertSame(
            ['https://example.test/cover.jpg', 'https://example.test/gallery.jpg'],
            $sections['sale'][0]['image_urls'],
        );

        $imageQueries = array_filter(
            $queries,
            fn (array $query) => preg_match('/\bfrom\s+["\x60]?property_images\b/i', $query['query']) === 1,
        );
        $this->assertCount(1, $imageQueries, 'The homepage should eager load images for all sections once.');
    }

    private function owner(): User
    {
        return User::query()->create([
            'name' => 'Discovery Search Owner',
            'email' => 'discovery-search@example.test',
            'phone' => '+967711111111',
            'phone_verified_at' => now(),
            'account_status' => User::STATUS_ACTIVE,
            'password' => Hash::make('StrongPass123!'),
        ]);
    }

    private function listing(User $owner, array $overrides): Property
    {
        return Property::query()->create(array_merge([
            'user_id' => $owner->id,
            'title' => 'عقار تجريبي',
            'description' => 'وصف الإعلان',
            'purpose' => 'sale',
            'type' => 'house',
            'price' => 50000000,
            'currency' => 'YER',
            'area_m2' => 200,
            'bedrooms' => 3,
            'bathrooms' => 2,
            'address' => 'صنعاء',
            'latitude' => 15.3694,
            'longitude' => 44.1910,
            'status' => 'published',
            'review_status' => 'approved',
            'availability_status' => 'available',
            'published_at' => now(),
            'contact_phone' => '+967700000000',
            'contact_whatsapp' => '+967700000000',
        ], $overrides));
    }
}
