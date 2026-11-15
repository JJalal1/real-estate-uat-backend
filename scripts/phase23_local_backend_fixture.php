<?php
/** Synthetic starting state and read-only observer. Never invokes journey writes. */
declare(strict_types=1);

$root = dirname(__DIR__);
// Run before Laravel bootstrap, database connection, migration or seeding.
$command = 'python3 -B '.escapeshellarg(__DIR__.'/phase23_local_media_guard.py');
exec($command, $guardLines, $guardExit);
if ($guardExit !== 0) throw new RuntimeException('Local fixture boundary refused.');
$boundary = json_decode(implode("\n", $guardLines), true, flags: JSON_THROW_ON_ERROR);
$mode = $argv[1] ?? '';
if ($mode === 'guard') { echo json_encode($boundary, JSON_THROW_ON_ERROR)."\n"; exit(0); }
if (!in_array($mode, ['seed', 'inspect'], true)) throw new RuntimeException('Expected guard, seed or inspect.');
$output = $argv[2] ?? '';
$privateRoot = rtrim((string)getenv('RUNNER_TEMP'), '/').'/phase23-local-media';
if (!str_starts_with($privateRoot, '/') || $output !== $privateRoot.'/fixture.json') throw new RuntimeException('Exact private fixture path required.');
require $root.'/backend-api-runtime/vendor/autoload.php';
$app = require $root.'/backend-api-runtime/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (!$app->environment('local') || config('database.default') !== 'pgsql'
    || config('database.connections.pgsql.host') !== '127.0.0.1'
    || config('database.connections.pgsql.database') !== 'phase23_local_media_ci'
    || (string)config('database.connections.pgsql.url') !== ''
    || config('services.supabase_storage.enabled') || config('push.enabled')) {
    throw new RuntimeException('Resolved runtime must remain local.');
}
$dbIdentity = Illuminate\Support\Facades\DB::selectOne('SELECT current_database() AS name, current_user AS actor');
if ($dbIdentity->name !== 'phase23_local_media_ci' || $dbIdentity->actor !== 'postgres') throw new RuntimeException('Disposable database identity mismatch.');

if ($mode === 'seed') {
    if (file_exists($output) || App\Models\User::query()->exists() || App\Models\Property::query()->exists()) {
        throw new RuntimeException('Seed requires a fresh, empty disposable database.');
    }
    if (!is_dir($privateRoot)) mkdir($privateRoot, 0700, true);
    $nonce = bin2hex(random_bytes(16));
    $actors = Illuminate\Support\Facades\DB::transaction(function (): array {
        $actors = [];
        foreach (['advertiser' => '101', 'support' => '102', 'researcher' => '103'] as $alias => $suffix) {
            $user = App\Models\User::query()->create([
                'name' => 'P23 Local '.ucfirst($alias), 'email' => 'p23-local-'.$alias.'@example.test',
                'phone' => '+967700230'.$suffix, 'password' => bin2hex(random_bytes(32)),
                'identity_policy_version' => 1, 'account_type' => 'regular', 'account_status' => 'active',
                'phone_verified_at' => now(), 'profile_completed_at' => now(),
            ]);
            app(App\Services\AccessControlService::class)->ensureRegisteredUser($user);
            if ($alias === 'support') {
                $role = App\Models\Role::query()->where('key', 'support_agent')->firstOrFail();
                $user->roles()->syncWithoutDetaching([$role->id => ['assigned_by_user_id' => null, 'created_at' => now()]]);
            }
            $actors[$alias] = ['id' => $user->id, 'phone' => $user->phone, 'email' => $user->email];
        }
        App\Models\AccountVerificationProfile::query()->create([
            'user_id' => $actors['advertiser']['id'], 'type' => 'broker', 'status' => 'approved',
            'details' => ['governorate' => 'Sanaa', 'district' => 'Synthetic Local District', 'work_areas' => ['Sanaa'], 'specialties' => ['houses']],
            'submitted_at' => now(), 'reviewed_at' => now(), 'reviewed_by_user_id' => $actors['support']['id'],
            'review_note' => 'Synthetic starting account only; account verification is outside this journey.',
        ]);
        return $actors;
    });
    $advertiser = App\Models\User::query()->findOrFail($actors['advertiser']['id']);
    $fields = [
        'listing_input_version' => 9, 'title' => 'P23 Local Media Original',
        'description' => 'Synthetic local property for image review and reader refresh acceptance.',
        'purpose' => 'sale', 'type' => 'house', 'tenure_type' => 'freehold', 'price' => 50000000,
        'currency' => 'YER', 'area_m2' => 220, 'area_value' => 220, 'area_unit' => 'sqm',
        'bedrooms' => 4, 'bathrooms' => 3, 'floors_count' => 2, 'units_per_floor' => [1, 1], 'has_parking' => true,
        'building_facade' => 'north', 'address' => 'صنعاء حي التجربة المحلية بيت 2301',
        'latitude' => 15.3694, 'longitude' => 44.1910,
        'contact_phone' => $advertiser->phone, 'contact_whatsapp' => $advertiser->phone,
    ];
    $schema = app(App\Services\DynamicPropertySchema::class);
    $fields = $schema->validateStructure($fields);
    foreach (array_merge(['address', 'price'], $schema->required($fields)) as $key) {
        if (!array_key_exists($key, $fields) || $fields[$key] === null || $fields[$key] === '') {
            throw new RuntimeException('Starting draft is missing a required field: '.$key);
        }
    }
    $asset = app(App\Services\PropertyIdentityService::class)->resolveOrCreateAsset($advertiser, $fields);
    $listing = App\Models\Property::query()->create($fields + [
        'user_id' => $advertiser->id, 'property_asset_id' => $asset->id,
        'status' => 'draft', 'review_status' => 'draft', 'owner_key' => null,
    ]);
    Illuminate\Support\Facades\DB::statement('UPDATE properties SET location = ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography WHERE id = ?', [$listing->longitude, $listing->latitude, $listing->id]);
    app(App\Services\PropertySaiService::class)->configure($advertiser, $listing, 'buyer', 0.0, null,
        Illuminate\Http\Request::create('http://127.0.0.1:8000/fixture-starting-state', 'POST'));
    $sources = [
        ['A-exterior.png', 'backend-api-runtime/public/demo-properties/property-exterior.png', 'good'],
        ['B-interior.png', 'backend-api-runtime/public/demo-properties/property-interior.png', 'good'],
        ['C-replacement.jpg', 'backend-api-runtime/resources/uat-wave3/images/villa.jpg', 'good'],
        ['X-brand-logo.png', 'mobile_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 'bad'],
    ];
    mkdir($privateRoot.'/files', 0700);
    $files = [];
    foreach ($sources as [$name, $relative, $kind]) {
        $path = $privateRoot.'/files/'.$name;
        if (!copy($root.'/'.$relative, $path)) throw new RuntimeException('Fixture media copy failed.');
        chmod($path, 0600);
        $files[] = ['name' => $name, 'path' => $path, 'source' => $relative, 'sha256' => hash_file('sha256', $path), 'kind' => $kind];
    }
    $fixture = $boundary + ['schema' => 1, 'nonce' => $nonce, 'app_env' => 'local', 'origin' => 'http://10.0.2.2:8000',
        'identity_path' => '/phase23-local-identity-'.$nonce.'.json', 'actors' => $actors,
        'listing_id' => $listing->id, 'title' => $fields['title'], 'updated_title' => 'P23 Local Media Updated',
        'files' => $files, 'scope' => 'Synthetic local starting state; all subsequent journey writes use the ordinary app UI. HTTP disk cache bypass is expected.'];
    file_put_contents($output, json_encode($fixture, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n");
    chmod($output, 0600);
    $identity = array_intersect_key($fixture, array_flip(['schema','marker','nonce','app_env','api','origin','database','source_sha','run_id','product_trees']));
    file_put_contents($root.'/backend-api-runtime/public'.$fixture['identity_path'], json_encode($identity, JSON_THROW_ON_ERROR)."\n");
    echo json_encode(['marker' => $fixture['marker'], 'seeded_users' => 3, 'seeded_drafts' => 1, 'seeded_images' => 0], JSON_THROW_ON_ERROR)."\n";
    exit(0);
}

// The observer is read-only, bounded to the single synthetic listing and its actors.
$fixture = json_decode(file_get_contents($output), true, flags: JSON_THROW_ON_ERROR);
foreach (['marker','source_sha','run_id','api','database'] as $key) {
    if (($fixture[$key] ?? null) !== $boundary[$key]) throw new RuntimeException('Observer fixture identity mismatch.');
}
if (!preg_match('/^[a-f0-9]{32}$/D', $fixture['nonce'] ?? '')) throw new RuntimeException('Observer nonce missing.');
$listing = App\Models\Property::query()->with(['images', 'reviews'])->findOrFail($fixture['listing_id']);
if ((int)$listing->user_id !== (int)$fixture['actors']['advertiser']['id']) throw new RuntimeException('Observer listing owner mismatch.');
$workflow = app(App\Services\ListingWorkflowService::class);
$states = $workflow->mediaReviewStates($listing);
$images = [];
foreach ($listing->images as $image) {
    $path = Illuminate\Support\Facades\Storage::disk(App\Services\ListingImageService::isPrivate($image->path) ? 'local' : 'public')->path($image->path);
    $images[] = ['id' => $image->id, 'sha256' => is_file($path) ? hash_file('sha256', $path) : null,
        'sort_order' => $image->sort_order, 'is_primary' => $image->is_primary,
        'fingerprint' => $workflow->mediaFingerprint($image),
        'relevance_status' => $states[$image->id]['decision'] ?? 'unreviewed', 'review' => $states[$image->id] ?? null];
}
$reviews = $listing->reviews->take(-60)->map(fn($review) => [
    'id' => $review->id, 'action' => $review->action, 'actor_user_id' => $review->actor_user_id,
    'from_status' => $review->from_review_status, 'to_status' => $review->to_review_status,
    'reason' => $review->reason, 'metadata' => $review->metadata,
])->values()->all();
$audits = App\Models\AuditLog::query()->where('subject_type', 'Property')->where('subject_id', $listing->id)
    ->orderByDesc('id')->limit(60)->get(['id','action','actor_user_id','request_method','request_path','metadata'])->reverse()->values()->toArray();
echo json_encode(['marker' => $fixture['marker'], 'nonce' => $fixture['nonce'], 'app_env' => app()->environment(),
    'api_origin' => $fixture['origin'], 'database' => $dbIdentity->name,
    'user_count' => App\Models\User::query()->count(), 'property_count' => App\Models\Property::query()->count(),
    'listing' => ['id' => $listing->id, 'title' => $listing->title, 'status' => $listing->status,
        'review_status' => $listing->review_status, 'last_review_reason' => $listing->last_review_reason,
        'images' => $images, 'reviews' => $reviews], 'audit_events' => $audits,
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n";
