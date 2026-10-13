<?php

namespace Database\Seeders;

use App\Models\AccountVerificationDocument;
use App\Models\AccountVerificationProfile;
use App\Models\AdvertiserRating;
use App\Models\BrokerCustomerFollowup;
use App\Models\MessageThread;
use App\Models\PrivateMessage;
use App\Models\Property;
use App\Models\PropertyImage;
use App\Models\Role;
use App\Models\User;
use App\Models\ViewingBooking;
use App\Models\ViewingBookingEvent;
use App\Services\BrokerDealService;
use App\Services\CloudAssetStorageService;
use App\Services\PropertyIdentityService;
use App\Services\PropertySaiService;
use App\Services\SupportTaskService;
use App\Services\UatWave3CleanupService;
use App\Services\UserNotificationService;
use Illuminate\Database\Seeder;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

class UatWave3MarketplaceSeeder extends Seeder
{
    public const MARKER = 'uat.marketplace.wave3.seeded';
    private int $sequence = 0;
    private array $publicPaths = [];
    private array $privatePaths = [];

    public function run(): void
    {
        $cleanup = app(UatWave3CleanupService::class);
        $cleanup->guard();
        if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) return;
        try {
            DB::transaction(function () use ($cleanup): void {
                if (DB::connection()->getDriverName() === 'pgsql') DB::select('SELECT pg_advisory_xact_lock(73101303)');
                if (DB::table('platform_settings')->where('key', self::MARKER)->exists()) return;
                $plan = $cleanup->plan();
                $protectedIds = DB::table('users')->whereNotIn('id', $plan['ids'])->pluck('id')->all();
                $protected = $this->protectedSnapshot($protectedIds);
                $backup = $cleanup->execute($plan);
                $users = $this->accounts();
                $buyers = [$users['buyer1'], $users['buyer2'], $users['renter'], $users['buyer3'], $users['regular']];
                $this->listing($users['owner'], 'apartment', 'sale', 'شقة عائلية مشرقة في حدة', 'published', 'available');
                $plans = [
                    'strong' => ['closed' => 6, 'active' => ['apartment', 'villa', 'land', 'office'], 'extra' => 'draft'],
                    'medium' => ['closed' => 3, 'active' => ['house', 'shop'], 'extra' => 'paused_due'],
                    'new' => ['closed' => 1, 'active' => ['apartment', 'farm'], 'extra' => 'pending'],
                    'office' => ['closed' => 1, 'active' => ['building', 'office'], 'extra' => 'returned'],
                ];
                foreach ($plans as $key => $persona) {
                    $actor = $users[$key];
                    for ($i = 0; $i < $persona['closed']; $i++) {
                        $property = $this->listing($actor, ['apartment', 'house', 'villa', 'shop'][$i % 4], $i % 2 ? 'rent' : 'sale', null, 'published', 'available');
                        $customer = $buyers[$i % count($buyers)];
                        $thread = $this->conversation($actor, $customer, $property, 'completed');
                        $request = Request::create('/uat/wave3/fixtures', 'POST');
                        $deal = app(BrokerDealService::class)->report($actor, $thread, null, $request);
                        $deal = app(BrokerDealService::class)->decide($customer, $deal, true, $request);
                        if ($i < count($buyers)) AdvertiserRating::create([
                            'broker_deal_outcome_id' => $deal->id, 'advertiser_user_id' => $actor->id, 'advertiser_name_snapshot' => $actor->name,
                            'rater_user_id' => $customer->id, 'rater_name_snapshot' => $customer->name, 'source_property_id' => $property->id,
                            'rating' => $key === 'strong' ? ($i === 3 ? 4 : 5) : ($key === 'medium' && $i === 1 ? 3 : 4),
                            'comment' => $key === 'strong' ? 'كان واضحًا في التفاصيل والتزم بموعد المعاينة، وساعدنا حتى إتمام الاتفاق.' : 'تواصل جيد وتفاصيل العقار مطابقة لما شاهدناه في المعاينة.', 'status' => 'visible',
                        ]);
                    }
                    foreach ($persona['active'] as $i => $type) {
                        $property = $this->listing($actor, $type, $i % 2 ? 'rent' : 'sale', null, 'published', 'available', $key === 'new' && $type === 'apartment');
                        $thread = $this->conversation($actor, $buyers[($i + 1) % count($buyers)], $property, $i ? 'viewing_scheduled' : 'contacted');
                        $this->viewing($actor, $buyers[($i + 1) % count($buyers)], $property, $thread, $i);
                        BrokerCustomerFollowup::create(['user_id' => $actor->id, 'message_thread_id' => $thread->id,
                            'private_note' => $i ? 'يرغب في موعد آخر بعد حضور أحد أفراد الأسرة.' : 'الميزانية مناسبة. إرسال تفاصيل الموقع قبل المعاينة.', 'remind_at' => now()->addHours($i + 2)]);
                    }
                    if ($persona['extra'] === 'paused_due') {
                        $this->listing($actor, 'apartment', 'rent', 'شقة قريبة من الخدمات في السبعين', 'published', 'paused');
                        $due = $this->listing($actor, 'land', 'sale', 'أرض سكنية على شارع فرعي واسع', 'published', 'available');
                        $due->forceFill(['availability_confirmed_at' => now()->subDays(15), 'availability_due_at' => now()->subHour(), 'availability_notified_at' => now()])->saveQuietly();
                        app(UserNotificationService::class)->create($actor->id, 'broker_availability_due', 'أكد توفر العقار', 'هذا الإعلان يحتاج تأكيد التوفر خلال يومين.', null, null, ['property_ids' => [$due->id], 'count' => 1, 'grace_days' => 2]);
                    } else {
                        $state = $persona['extra'];
                        $this->listing($actor, $key === 'office' ? 'shop' : 'house', 'sale', null, $state, 'available');
                    }
                }
                if ($protected !== $this->protectedSnapshot($protectedIds)) throw new RuntimeException('Protected operational account snapshot changed; rolling back.');
                DB::table('platform_settings')->insert(['key' => self::MARKER, 'value' => json_encode([
                    'version' => 3, 'seeded_at' => now()->toIso8601String(), 'fixture_users' => count($users), 'fixture_properties' => $this->sequence,
                    'protected_user_ids' => $protectedIds, 'cleanup' => $backup,
                ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR), 'value_type' => 'json', 'group_key' => 'uat', 'label_ar' => 'اكتمال محتوى UAT للموجة الثالثة', 'is_public' => false, 'created_at' => now(), 'updated_at' => now()]);
                app(SupportTaskService::class)->syncSources();
            });
        } catch (\Throwable $error) {
            foreach ($this->publicPaths as $path) app(CloudAssetStorageService::class)->deletePublic($path);
            foreach ($this->privatePaths as $path) app(CloudAssetStorageService::class)->deletePrivate($path);
            throw $error;
        }
        $this->command?->info('Wave3 UAT marketplace seeded: 11 personas, 27 listings; operational accounts preserved.');
    }

    private function protectedSnapshot(array $ids): string
    {
        $profiles = DB::table('account_verification_profiles')->whereIn('user_id', $ids)->pluck('id')->all();
        return hash('sha256', json_encode([
            DB::table('users')->whereIn('id', $ids)->orderBy('id')->get()->all(),
            DB::table('user_role')->whereIn('user_id', $ids)->orderBy('user_id')->orderBy('role_id')->get()->all(),
            DB::table('user_permission_overrides')->whereIn('user_id', $ids)->orderBy('id')->get()->all(),
            DB::table('account_verification_profiles')->whereIn('id', $profiles)->orderBy('id')->get()->all(),
            DB::table('account_verification_documents')->whereIn('profile_id', $profiles)->orderBy('id')->get()->all(),
        ], JSON_THROW_ON_ERROR));
    }

    private function accounts(): array
    {
        $definitions = [
            ['owner', 1, 'عبدالله محمد علي القاضي', 'owner', null],
            ['regular', 2, 'سارة أحمد صالح الحضرمي', null, null],
            ['new', 3, 'فارس علي أحمد العنسي', 'broker', 'broker_new'],
            ['strong', 4, 'أحمد محمد علي الجبري', 'broker', 'broker_senior'],
            ['medium', 5, 'ماهر عبدالله محمد الصبري', 'broker', 'broker_mid'],
            ['office', 10, 'مكتب ركن الدار العقاري', 'office', 'building'],
            ['buyer1', 11, 'خالد إبراهيم حسن العمري', null, null],
            ['buyer2', 12, 'مريم صالح أحمد المقطري', null, null],
            ['renter', 13, 'يوسف علي محمود القدسي', null, null],
            ['buyer3', 14, 'هناء حسين أحمد عبد الولي', null, null],
            ['pending', 15, 'سمير عبدالرحمن علي الحداد', 'broker', null],
        ];
        $users = [];
        foreach ($definitions as [$key, $suffix, $name, $type, $photo]) {
            $phone = '+120255501'.str_pad((string) $suffix, 2, '0', STR_PAD_LEFT);
            if (User::where('phone', $phone)->exists()) throw new RuntimeException('A fixture phone belongs to a protected/unscoped account.');
            $user = User::create(['name' => $name, 'phone' => $phone, 'email' => 'wave3-'.$key.'@example.invalid', 'password' => Str::random(48),
                'account_status' => 'active', 'identity_policy_version' => 2, 'phone_verified_at' => now(), 'profile_completed_at' => now(),
                'account_type' => $type === 'broker' ? 'broker' : 'regular', 'broker_verification_status' => $type === 'broker' ? ($key === 'pending' ? 'pending' : 'approved') : 'not_required',
                'broker_verified_at' => $type === 'broker' && $key !== 'pending' ? now() : null]);
            $roles = [Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()]];
            if ($type === 'broker' && $key !== 'pending') $roles[Role::where('key', 'broker')->firstOrFail()->id] = ['created_at' => now()];
            $user->roles()->sync($roles);
            if ($type) {
                $details = ['governorate' => 'صنعاء', 'district' => 'السبعين', 'work_areas' => ['حدة', 'بيت بوس', 'السنينة'], 'specialties' => ['شقق سكنية', 'عقارات تجارية'], 'uat_fixture' => true];
                if ($type === 'office') $details += ['office_name' => $name, 'commercial_register_number' => 'UAT-WAVE3-OFFICE', 'neighborhood' => 'حدة', 'street' => 'شارع الخمسين', 'landmark' => 'قرب الحديقة', 'latitude' => 15.328, 'longitude' => 44.196, 'office_phone' => $phone];
                $profile = AccountVerificationProfile::create(['user_id' => $user->id, 'type' => $type, 'status' => $key === 'pending' ? 'pending' : 'approved', 'details' => $details,
                    'submitted_at' => now()->subDays(3), 'reviewed_at' => $key === 'pending' ? null : now()->subDays(2), 'review_note' => 'UAT Wave3 fictional persona; no real identity asserted.']);
                $kinds = $type === 'office' ? ['identity_document', 'selfie', 'commercial_register', 'office_license', 'office_frontage'] : ['identity_document', 'selfie'];
                foreach ($kinds as $kind) $this->verificationFixture($profile, $kind);
            }
            if ($photo) $user->forceFill(['public_professional_photo_path' => $this->photo($photo, 'uat-wave3/portraits/'.$key),
                'public_professional_bio' => $key === 'strong' ? 'أساعد الأسر على اختيار العقار المناسب في صنعاء. أركز على وضوح التفاصيل والالتزام بالمواعيد.' : 'أتابع عروض البيع والإيجار في صنعاء، وأرتب المعاينات حسب الوقت المناسب للعميل.'])->saveQuietly();
            $users[$key] = $user->fresh();
        }
        return $users;
    }

    private function verificationFixture(AccountVerificationProfile $profile, string $kind): void
    {
        $image = imagecreatetruecolor(720, 300);
        imagefilledrectangle($image, 0, 0, 719, 299, imagecolorallocate($image, 238, 242, 245));
        $ink = imagecolorallocate($image, 35, 45, 60);
        imagestring($image, 5, 35, 65, 'UAT FIXTURE - NOT AN IDENTITY DOCUMENT', $ink);
        imagestring($image, 5, 35, 115, 'Wave 3 / profile '.$profile->id.' / '.$kind, $ink);
        imagestring($image, 5, 35, 165, 'FICTIONAL PERSONA / TESTING ONLY', $ink);
        $temp = tempnam(sys_get_temp_dir(), 'wave3-evidence-');
        try {
            imagepng($image, $temp);
            $path = app(CloudAssetStorageService::class)->storePrivate(new UploadedFile($temp, 'uat-fixture.png', 'image/png', null, true), 'uat-wave3/verification/'.$profile->id);
            $this->privatePaths[] = $path;
            AccountVerificationDocument::create(['profile_id' => $profile->id, 'kind' => $kind, 'path' => $path, 'original_name' => 'UAT-FIXTURE.png', 'mime_type' => 'image/png', 'size_bytes' => filesize($temp)]);
        } finally {
            imagedestroy($image);
            if (is_file($temp)) unlink($temp);
        }
    }

    private function photo(string $name, string $directory): string
    {
        $file = resource_path('uat-wave3/images/'.$name.'.jpg');
        $path = app(CloudAssetStorageService::class)->storePublic(new UploadedFile($file, $name.'.jpg', 'image/jpeg', null, true), $directory);
        $this->publicPaths[] = $path;
        return $path;
    }

    private function listing(User $actor, string $type, string $purpose, ?string $title, string $state, string $availability, bool $wholeFloor = false): Property
    {
        $index = ++$this->sequence;
        $district = ['حدة', 'بيت بوس', 'السنينة', 'السبعين'][$index % 4];
        $names = ['apartment' => 'شقة واسعة', 'house' => 'منزل عائلي', 'villa' => 'فيلا بحديقة', 'building' => 'عمارة استثمارية', 'land' => 'أرض سكنية', 'farm' => 'مزرعة بمدرجات خضراء', 'shop' => 'محل على شارع تجاري', 'office' => 'مكتب مضاء طبيعيًا'];
        $price = ['apartment' => 65000000, 'house' => 95000000, 'villa' => 190000000, 'building' => 310000000, 'land' => 28000000, 'farm' => 45000000, 'shop' => 35000000, 'office' => 42000000][$type];
        $monthly = ['apartment' => 180000, 'house' => 320000, 'villa' => 550000, 'building' => 1600000, 'land' => 90000, 'farm' => 140000, 'shop' => 220000, 'office' => 160000][$type];
        $residential = in_array($type, ['apartment', 'house', 'villa'], true);
        $unit = in_array($type, ['apartment', 'office', 'shop'], true);
        $data = ['listing_input_version' => 5, 'title' => $title ?? ($names[$type].' '.($purpose === 'sale' ? 'للبيع' : 'للإيجار').' في '.$district),
            'description' => 'عقار في منطقة '.$district.' بصنعاء، قريب من الخدمات والطريق الرئيسي. يمكن ترتيب معاينة للتأكد من المساحة والمواصفات قبل الاتفاق.',
            'purpose' => $purpose, 'type' => $type, 'tenure_type' => $purpose === 'sale' ? 'freehold' : null,
            'price' => $purpose === 'rent' ? $monthly * 3 : $price + $index * 150000, 'monthly_rent' => $purpose === 'rent' ? $monthly : null,
            'rental_term_months' => $purpose === 'rent' ? 12 : null, 'advance_months' => $purpose === 'rent' ? 3 : null,
            'currency' => 'YER', 'area_m2' => $type === 'farm' ? 2200 : ($type === 'building' ? 420 : ($type === 'land' ? 360 : 110 + $index * 4)),
            'area_unit' => 'sqm', 'bedrooms' => $residential ? 3 + $index % 2 : null, 'bathrooms' => $residential ? 2 : null,
            'has_parking' => in_array($type, ['house', 'villa', 'building'], true), 'building_facade' => in_array($type, ['land', 'farm'], true) ? null : 'south',
            'address' => 'صنعاء، '.$district.'، شارع فرعي قرب الخدمات', 'latitude' => 15.31 + $index * 0.0018, 'longitude' => 44.16 + $index * 0.0014,
            'floor_number' => $unit && $type !== 'shop' ? (string) (1 + $index % 4) : null, 'unit_number' => $unit && ! $wholeFloor ? ($index % 2 ? 'أمامية' : 'جنوبية') : null,
            'unit_occupies_entire_floor' => $type === 'apartment' && $wholeFloor, 'status' => 'draft', 'review_status' => 'draft',
            'contact_phone' => $actor->phone, 'contact_whatsapp' => $actor->phone, 'ownership_document_type' => 'purchase_deed',
            'document_owner_name' => $actor->name, 'owner_relationship_type' => $actor->isOwnerVerified() ? 'owner' : 'agent'];
        $data['area_value'] = $data['area_m2'];
        app(PropertyIdentityService::class)->validateIdentityInput($data);
        $asset = app(PropertyIdentityService::class)->resolveOrCreateAsset($actor, $data);
        unset($data['listing_input_version']);
        $property = Property::create($data + ['user_id' => $actor->id, 'property_asset_id' => $asset->id]);
        $photo = ['house' => 'villa', 'farm' => 'land'][$type] ?? $type;
        PropertyImage::create(['property_id' => $property->id, 'path' => $this->photo($photo, 'uat-wave3/listings/'.$property->id), 'sort_order' => 0, 'is_primary' => true]);
        $proofImage = imagecreatetruecolor(720, 240);
        imagefilledrectangle($proofImage, 0, 0, 719, 239, imagecolorallocate($proofImage, 238, 242, 245));
        $ink = imagecolorallocate($proofImage, 35, 45, 60);
        imagestring($proofImage, 5, 30, 60, 'UAT OWNERSHIP/AUTHORIZATION FIXTURE', $ink);
        imagestring($proofImage, 5, 30, 105, 'NOT A LEGAL DOCUMENT / listing '.$property->id, $ink);
        $temp = tempnam(sys_get_temp_dir(), 'wave3-listing-proof-');
        try {
            imagepng($proofImage, $temp);
            $proofPath = app(CloudAssetStorageService::class)->storePrivate(new UploadedFile($temp, 'uat-relationship.png', 'image/png', null, true), 'uat-wave3/listing-proofs/'.$property->id);
            $this->privatePaths[] = $proofPath;
            $property->documents()->create(['uploaded_by_user_id' => $actor->id, 'kind' => $actor->isOwnerVerified() ? 'ownership_proof' : 'ownership_or_authorization',
                'path' => $proofPath, 'original_name' => 'UAT-RELATIONSHIP-FIXTURE.png', 'mime_type' => 'image/png', 'size_bytes' => filesize($temp), 'created_at' => now()]);
        } finally { imagedestroy($proofImage); if (is_file($temp)) unlink($temp); }
        app(PropertySaiService::class)->configure($actor, $property, $purpose === 'sale' ? 'buyer' : 'tenant', $actor->isOwnerVerified() ? null : ($purpose === 'sale' ? 2 : 50), $actor->isOwnerVerified() ? null : 'accept', Request::create('/uat/wave3/fixtures', 'POST'));
        $review = match ($state) { 'published' => 'approved', 'pending' => 'submitted', 'returned' => 'returned_for_correction', default => 'draft' };
        $property->forceFill(['status' => $state === 'returned' ? 'draft' : $state, 'review_status' => $review,
            'submitted_at' => $state !== 'draft' ? now()->subHours(3) : null, 'published_at' => $state === 'published' ? now()->subDays($index % 8) : null,
            'reviewed_at' => in_array($state, ['published', 'returned'], true) ? now()->subHours(2) : null,
            'last_review_reason' => $state === 'returned' ? 'وضح مساحة المحل وأرفق مستند العلاقة بالعقار.' : null,
            'availability_status' => $availability, 'availability_confirmed_at' => now(), 'availability_due_at' => now()->addDays($purpose === 'rent' ? 7 : 14)])->saveQuietly();
        if ($state === 'published') app(PropertyIdentityService::class)->ensureRepresentation($property);
        if ($state !== 'draft') DB::table('listing_reviews')->insert(['listing_id' => $property->id, 'action' => 'uat_wave3_fixture', 'actor_name_snapshot' => 'UAT fixture setup',
            'from_review_status' => 'draft', 'to_review_status' => $review, 'reason' => 'Fictional UAT marketplace fixture, not a production review.',
            'listing_snapshot' => json_encode(['id' => $property->id, 'title' => $property->title, 'status' => $property->status, 'review_status' => $review]), 'metadata' => json_encode(['uat_wave3' => true]), 'created_at' => now()]);
        if (DB::connection()->getDriverName() === 'pgsql') DB::statement('UPDATE properties SET location=ST_SetSRID(ST_MakePoint(longitude,latitude),4326)::geography WHERE id=?', [$property->id]);
        return $property->fresh();
    }

    private function conversation(User $actor, User $customer, Property $property, string $stage): MessageThread
    {
        $thread = MessageThread::create(['property_id' => $property->id, 'started_by_user_id' => $customer->id,
            'conversation_key' => 'property:'.$property->id.':user:'.$customer->id, 'last_message_at' => now()->subMinutes(12), 'lead_stage' => $stage, 'lead_updated_at' => now()]);
        foreach ([$actor, $customer] as $participant) $thread->participants()->create(['user_id' => $participant->id, 'user_name_snapshot' => $participant->name]);
        PrivateMessage::create(['thread_id' => $thread->id, 'sender_user_id' => $customer->id, 'sender_name_snapshot' => $customer->name, 'body' => 'السلام عليكم، هل العقار ما زال متاحًا؟ أود معرفة موعد مناسب للمعاينة.', 'created_at' => now()->subMinutes(20)]);
        PrivateMessage::create(['thread_id' => $thread->id, 'sender_user_id' => $actor->id, 'sender_name_snapshot' => $actor->name, 'body' => 'وعليكم السلام. يسعدني ترتيب المعاينة وإرسال تفاصيل الموقع. هل يناسبك وقت العصر؟', 'created_at' => now()->subMinutes(12)]);
        app(UserNotificationService::class)->create($customer->id, 'message_received', 'رسالة من '.$actor->name, 'تحديث بخصوص العقار الذي تواصلت بشأنه.', 'message_thread', $thread->id, ['thread_id' => $thread->id, 'property_id' => $property->id]);
        DB::table('property_listing_views')->insert(['property_id' => $property->id, 'viewer_hash' => hash('sha256', 'wave3:'.$customer->id.':'.$property->id), 'view_date' => now()->toDateString(), 'created_at' => now()]);
        $property->forceFill(['view_count' => 1])->saveQuietly();
        DB::table('property_favorites')->insert(['user_id' => $customer->id, 'property_id' => $property->id, 'created_at' => now(), 'updated_at' => now()]);
        return $thread;
    }

    private function viewing(User $actor, User $customer, Property $property, MessageThread $thread, int $position): void
    {
        $start = now()->startOfHour()->addHours(1 + $position);
        $booking = ViewingBooking::create(['reference' => 'VIEW-'.strtoupper(Str::random(12)), 'requester_user_id' => $customer->id, 'requester_name_snapshot' => $customer->name,
            'host_user_id' => $actor->id, 'host_name_snapshot' => $actor->name, 'message_thread_id' => $thread->id, 'target_type' => 'property', 'target_id' => $property->id,
            'target_title_snapshot' => $property->title, 'target_address_snapshot' => $property->address, 'starts_at' => $start, 'ends_at' => $start->copy()->addMinutes(45), 'timezone' => 'Asia/Aden',
            'status' => $position ? 'requested' : 'confirmed', 'requester_note' => 'سأحضر مع أحد أفراد الأسرة.', 'confirmed_at' => $position ? null : now()]);
        ViewingBookingEvent::create(['viewing_booking_id' => $booking->id, 'actor_user_id' => $customer->id, 'actor_name_snapshot' => $customer->name,
            'event' => 'requested', 'to_status' => 'requested', 'metadata' => ['uat_wave3' => true], 'created_at' => now()]);
        app(UserNotificationService::class)->create($actor->id, 'booking_requested', 'طلب معاينة جديد', 'راجع الوقت المقترح للمعاينة.', 'viewing_booking', $booking->id, ['booking_id' => $booking->id, 'thread_id' => $thread->id]);
    }
}
