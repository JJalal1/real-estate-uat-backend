<?php

namespace Tests\Feature;

use App\Models\Property;
use App\Models\Role;
use App\Models\User;
use App\Models\ListingVideo;
use App\Services\CloudAssetStorageService;
use Illuminate\Support\Facades\DB;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

class ListingVideoApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config()->set('listing_video.processing_enabled', true);
        config()->set('listing_video.worker_heartbeat_required', false);
        Queue::fake();
    }

    private function actor(string $name): array
    {
        $user = User::query()->create([
            'name' => 'Test advertiser',
            'email' => $name.'@video.example.test',
            'phone' => '+9677331'.str_pad((string) (abs(crc32($name)) % 10000), 4, '0', STR_PAD_LEFT),
            'password' => Hash::make('VideoPass123!'),
            'account_status' => User::STATUS_ACTIVE,
            'phone_verified_at' => now(),
            'profile_completed_at' => now(),
            'identity_policy_version' => 2,
        ]);
        $user->roles()->sync([
            Role::where('key', 'registered_user')->firstOrFail()->id => ['created_at' => now()],
        ]);
        $token = 'test-video-'.$name;
        $user->apiTokens()->create([
            'name' => 'test',
            'token_hash' => hash('sha256', $token),
            'token_prefix' => substr($token, 0, 12),
            'expires_at' => now()->addHour(),
        ]);
        return [$user, ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json']];
    }

    private function property(User $user): Property
    {
        return Property::query()->create([
            'user_id' => $user->id,
            'title' => 'Video listing',
            'type' => 'shop',
            'purpose' => 'rent',
            'price' => 70000,
            'currency' => 'YER',
            'address' => 'Sanaa',
            'latitude' => 15.2,
            'longitude' => 44.1,
            'status' => 'draft',
            'review_status' => 'draft',
        ]);
    }

    private function video(): UploadedFile
    {
        $header = pack('N', 24).'ftypisom'.pack('N', 0).'isom';
        return UploadedFile::fake()->createWithContent('clip.mp4', $header.str_repeat("\0", 8));
    }

    public function test_owned_draft_video_upload_is_idempotent_and_original_is_private(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        // Uploads must fail closed when the asynchronous worker is not enabled.
        // Queue::fake() in setUp() isolates this API regression from the worker.
        config()->set('listing_video.processing_enabled', true);
        Storage::fake('local');
        Storage::fake('public');
        [$user, $headers] = $this->actor('owner');
        $property = $this->property($user);
        $key = (string) Str::uuid();
        $url = '/api/properties/'.$property->id.'/video';

        $this->withHeaders($headers)->post($url, [
            'upload_id' => $key, 'video' => $this->video(),
        ])->assertStatus(202)->assertJsonPath('data.status', 'uploaded');
        $this->assertDatabaseCount('listing_videos', 1);
        $record = ListingVideo::query()->firstOrFail();
        Storage::disk('local')->assertExists($record->original_path);
        $this->assertSame([], Storage::disk('public')->allFiles());

        $this->withHeaders($headers)->post($url, [
            'upload_id' => $key, 'video' => $this->video(),
        ])->assertStatus(202)->assertJsonPath('data.id', $record->id);
        $this->assertDatabaseCount('listing_videos', 1);

        $this->withHeaders($headers)->getJson($url)->assertOk()->assertJsonPath('data.status', 'uploaded');
        $this->withHeaders($headers)->deleteJson($url)->assertOk();
        $this->assertDatabaseCount('listing_videos', 0);
        Storage::disk('local')->assertMissing($record->original_path);
    }

    public function test_foreign_user_cannot_read_or_replace_unpublished_video(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        Storage::fake('local');
        [$owner, $ownerHeaders] = $this->actor('video-owner');
        [, $attackerHeaders] = $this->actor('video-attacker');
        $property = $this->property($owner);
        $url = '/api/properties/'.$property->id.'/video';

        $this->withHeaders($ownerHeaders)->post($url, [
            'upload_id' => (string) Str::uuid(),
            'video' => $this->video(),
        ])->assertStatus(202);

        $this->withHeaders($attackerHeaders)->getJson($url)->assertNotFound();
        $this->withHeaders($attackerHeaders)->post($url, [
            'upload_id' => (string) Str::uuid(), 'video' => $this->video(),
        ])->assertNotFound();
        $this->withHeaders($attackerHeaders)->deleteJson($url)->assertNotFound();
        $this->assertDatabaseCount('listing_videos', 1);
    }

    public function test_delete_failure_retains_tracked_video_for_a_successful_retry(): void
    {
        config(['listing_video.uploads_enabled'=>true]);
        Storage::fake('local');
        [$owner,$headers]=$this->actor('delete-failure');
        $property=$this->property($owner);
        $url='/api/properties/'.$property->id.'/video';
        $this->withHeaders($headers)->post($url,['upload_id'=>(string)Str::uuid(),'video'=>$this->video()])->assertStatus(202);
        $video=ListingVideo::query()->firstOrFail();
        $storage=new class extends CloudAssetStorageService {
            public function deletePrivate(string $path): void { throw new \RuntimeException('synthetic-delete-failure'); }
        };
        $request=\Illuminate\Http\Request::create($url,'DELETE');
        $request->setUserResolver(fn ()=>$owner);
        $controller=new \App\Http\Controllers\Api\ListingVideoController($storage,app(\App\Services\ListingVideoUploadPolicy::class),app(\App\Services\ListingVideoWorkerHealth::class));
        try { $controller->remove($request,$property); $this->fail('Storage failure must not acknowledge deletion'); }
        catch (\RuntimeException $error) { $this->assertSame('synthetic-delete-failure',$error->getMessage()); }
        $this->assertDatabaseHas('listing_videos',['id'=>$video->id]);
        Storage::disk('local')->assertExists($video->original_path);
        $this->withHeaders($headers)->deleteJson($url)->assertOk();
        $this->assertDatabaseCount('listing_videos',0);
        Storage::disk('local')->assertMissing($video->original_path);
    }

    public function test_account_erasure_does_not_race_an_active_video_writer(): void
    {
        config(['listing_video.uploads_enabled'=>true]);
        Storage::fake('local');
        [$owner,$headers]=$this->actor('erasure-writer');
        $property=$this->property($owner);
        $url='/api/properties/'.$property->id.'/video';
        $this->withHeaders($headers)->post($url,['upload_id'=>(string)Str::uuid(),'video'=>$this->video()])->assertStatus(202);
        $video=ListingVideo::query()->firstOrFail();
        $video->update(['status'=>'processing']);
        $request=\Illuminate\Http\Request::create('/api/account','DELETE');
        $request->setUserResolver(fn ()=>$owner);
        try { app(\App\Services\AccountErasureService::class)->erase($owner,$request); $this->fail('An active writer must quiesce before erasure'); }
        catch (\Symfony\Component\HttpKernel\Exception\ConflictHttpException $error) { $this->assertSame(409,$error->getStatusCode()); }
        $this->assertSame(User::STATUS_ACTIVE,$owner->fresh()->account_status);
        Storage::disk('local')->assertExists($video->original_path);
        $video->update(['status'=>'failed']);
        app(\App\Services\AccountErasureService::class)->erase($owner->fresh(),$request);
        $this->assertSame(User::STATUS_DELETED,$owner->fresh()->account_status);
        Storage::disk('local')->assertMissing($video->original_path);
        $this->assertDatabaseCount('listing_videos',0);
    }

    public function test_published_listing_does_not_accept_new_video_even_from_owner(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        [$owner, $headers] = $this->actor('published-owner');
        $property = $this->property($owner);
        $property->forceFill(['status' => 'published', 'review_status' => 'approved'])->save();
        $this->withHeaders($headers)->post('/api/properties/'.$property->id.'/video', [
            'upload_id' => (string) Str::uuid(),
            'video' => $this->video(),
        ])->assertStatus(409);
    }
    public function test_remote_video_upload_never_holds_a_database_transaction(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('services.supabase_storage.enabled', false);
        Storage::fake('local');
        $storage = new class extends CloudAssetStorageService {
            public ?int $openTransactionsDuringUpload = null;

            public function writePrivateFromFile(string $path, string $source, string $mime): void
            {
                $this->openTransactionsDuringUpload = DB::connection()->transactionLevel();
                parent::writePrivateFromFile($path, $source, $mime);
            }
        };
        app()->instance(CloudAssetStorageService::class, $storage);
        [$owner, $headers] = $this->actor('no-db-lock');
        $property = $this->property($owner);
        $baseline = DB::connection()->transactionLevel();
        $this->withHeaders($headers)->post('/api/properties/'.$property->id.'/video', [
            'upload_id' => (string) Str::uuid(), 'video' => $this->video(),
        ])->assertStatus(202);
        // RefreshDatabase wraps tests in an outer transaction; no additional
        // application-level transaction is allowed during external I/O.
        $this->assertSame($baseline, $storage->openTransactionsDuringUpload);
        $this->assertDatabaseHas('listing_videos', [
            'property_id' => $property->id, 'status' => 'uploaded',
        ]);
    }

    public function test_failed_private_upload_can_retry_same_idempotency_key_safely(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('services.supabase_storage.enabled', false);
        Storage::fake('local');
        $storage = new class extends CloudAssetStorageService {
            public bool $failNextUpload = true;

            public function writePrivateFromFile(string $path, string $source, string $mime): void
            {
                if ($this->failNextUpload) {
                    $this->failNextUpload = false;
                    throw new \RuntimeException('Synthetic cloud interruption');
                }
                parent::writePrivateFromFile($path, $source, $mime);
            }
        };
        app()->instance(CloudAssetStorageService::class, $storage);
        [$owner, $headers] = $this->actor('retry-after-fail');
        $property = $this->property($owner);
        $url = '/api/properties/'.$property->id.'/video';
        $key = (string) Str::uuid();

        $this->withHeaders($headers)->post($url, [
            'upload_id' => $key, 'video' => $this->video(),
        ])->assertStatus(500);
        $failed = ListingVideo::query()->firstOrFail();
        $this->assertSame('upload_failed', $failed->status);
        $oldPath = $failed->original_path;
        Storage::disk('local')->assertMissing($oldPath);

        $this->withHeaders($headers)->post($url, [
            'upload_id' => $key, 'video' => $this->video(),
        ])->assertStatus(202)->assertJsonPath('data.status', 'uploaded');

        $accepted = ListingVideo::query()->firstOrFail();
        $this->assertSame($failed->id, $accepted->id);
        $this->assertNotSame($oldPath, $accepted->original_path);
        Storage::disk('local')->assertExists($accepted->original_path);
        $this->assertDatabaseCount('listing_videos', 1);
    }

    public function test_new_upload_fails_closed_without_healthy_processing_worker(): void
    {
        config()->set('listing_video.uploads_enabled', true);
        config()->set('listing_video.worker_heartbeat_required', true);
        [$owner, $headers] = $this->actor('no-worker');
        $property = $this->property($owner);
        $url = '/api/properties/'.$property->id.'/video';
        $payload = ['upload_id' => 'not-a-uuid'];
        $this->withHeaders($headers)->post($url, $payload)->assertStatus(503);
        $this->assertDatabaseCount('listing_videos', 0);

        // An idle worker records its heartbeat via Laravel Queue::looping.
        app(\App\Services\ListingVideoWorkerHealth::class)->beat();
        $this->withHeaders($headers)->post($url, $payload)->assertStatus(422);

        DB::table('listing_video_worker_health')->where('id', 1)->update([
            'last_seen_at' => now()->subMinutes(15),
        ]);
        $this->withHeaders($headers)->post($url, $payload)->assertStatus(503);
        $this->assertDatabaseCount('listing_videos', 0);
    }

    public function test_failed_cleanup_keeps_superseded_originals_tracked_until_retry(): void
    {
        config(['listing_video.uploads_enabled'=>true,'services.supabase_storage.enabled'=>false]);
        Storage::fake('local');
        [$owner,$headers]=$this->actor('cleanup-tombstone');
        $property=$this->property($owner);$key=(string)Str::uuid();
        $url='/api/properties/'.$property->id.'/video';
        $storage=new class extends CloudAssetStorageService {
            public bool $fail=false;
            public function deletePrivate(string $path): void {
                if($this->fail) throw new \RuntimeException('synthetic-cleanup-unavailable');
                parent::deletePrivate($path);
            }
        };
        app()->instance(CloudAssetStorageService::class,$storage);
        $this->withHeaders($headers)->post($url,['upload_id'=>$key,'video'=>$this->video()])->assertStatus(202);
        $record=ListingVideo::query()->firstOrFail();$oldPath=$record->original_path;
        $record->update(['status'=>'upload_failed']);$storage->fail=true;
        $this->withHeaders($headers)->post($url,['upload_id'=>$key,'video'=>$this->video()])->assertStatus(500);
        $this->assertContains($oldPath,$record->fresh()->trackedPaths());
        Storage::disk('local')->assertExists($oldPath);
        $storage->fail=false;
        $this->withHeaders($headers)->post($url,['upload_id'=>$key,'video'=>$this->video()])->assertStatus(202);
        Storage::disk('local')->assertMissing($oldPath);
        $this->assertNull($record->fresh()->cleanup_paths);
    }

    public function test_authenticated_owner_is_still_denied_when_either_video_gate_is_closed(): void
    {
        [$owner,$headers]=$this->actor('feature-gates');
        $property=$this->property($owner);$url='/api/properties/'.$property->id.'/video';
        config(['listing_video.uploads_enabled'=>false]);
        $this->withHeaders($headers)->getJson($url)->assertNotFound();
        $this->withHeaders($headers)->postJson($url,['upload_id'=>'invalid'])->assertNotFound();
        $this->withHeaders($headers)->deleteJson($url)->assertNotFound();
        config(['listing_video.uploads_enabled'=>true,'listing_video.processing_enabled'=>false]);
        $this->withHeaders($headers)->postJson($url,['upload_id'=>'invalid'])->assertNotFound();
        $this->assertDatabaseCount('listing_videos',0);
    }

    public function test_stale_processing_attempt_cannot_erase_a_newer_attempts_output(): void
    {
        config(['listing_video.uploads_enabled'=>true,'listing_video.processing_enabled'=>true,
            'services.supabase_storage.enabled'=>false]);
        Storage::fake('local');
        [$owner,$headers]=$this->actor('stale-attempt');
        $property=$this->property($owner);
        $this->withHeaders($headers)->post('/api/properties/'.$property->id.'/video',
            ['upload_id'=>(string)Str::uuid(),'video'=>$this->video()])->assertStatus(202);
        $video=ListingVideo::query()->firstOrFail();
        $storage=new class($video->id) extends CloudAssetStorageService {
            public function __construct(private int $videoId) {}
            public function downloadPrivateToPath(string $path,string $target): void {
                $record=ListingVideo::query()->findOrFail($this->videoId);
                [$playback,$poster]=$record->derivativePathsForAttempt(2);
                Storage::disk('local')->put($playback,'newer-accepted-bytes');
                Storage::disk('local')->put($poster,'newer-accepted-poster');
                $record->update(['status'=>'ready','attempts'=>2,'playback_path'=>$playback,'poster_path'=>$poster]);
                throw new \RuntimeException('stale-worker-resumed');
            }
        };
        try {
            (new \App\Jobs\ProcessListingVideo($video->id))->handle($storage,app(\App\Services\ListingVideoTranscoder::class));
            $this->fail('Expected interruption');
        } catch (\RuntimeException $error) { $this->assertSame('stale-worker-resumed',$error->getMessage()); }
        $ready=$video->fresh();
        $this->assertSame('ready',$ready->status);$this->assertSame(2,$ready->attempts);
        $this->assertSame('newer-accepted-bytes',Storage::disk('local')->get($ready->playback_path));
        $this->assertSame('newer-accepted-poster',Storage::disk('local')->get($ready->poster_path));
    }

    public function test_listing_deletion_preserves_video_paths_on_failure_and_rejects_an_active_writer(): void
    {
        config(['listing_video.uploads_enabled'=>true,'services.supabase_storage.enabled'=>false]);
        Storage::fake('local');
        $storage=new class extends CloudAssetStorageService {
            public bool $fail=false;
            public function deletePrivate(string $path): void {
                if($this->fail) throw new \RuntimeException('synthetic-video-delete-failure');
                parent::deletePrivate($path);
            }
        };
        app()->instance(CloudAssetStorageService::class,$storage);
        [$owner,$headers]=$this->actor('listing-delete');$property=$this->property($owner);
        $url='/api/properties/'.$property->id;
        $this->withHeaders($headers)->post($url.'/video',['upload_id'=>(string)Str::uuid(),'video'=>$this->video()])->assertStatus(202);
        $video=ListingVideo::query()->firstOrFail();$video->update(['status'=>'processing']);
        $this->withHeaders($headers)->deleteJson($url)->assertStatus(409);
        $video->update(['status'=>'failed','attempts'=>1]);
        [$partial]=$video->derivativePathsForAttempt(1);Storage::disk('local')->put($partial,'partial');
        $storage->fail=true;
        $this->withHeaders($headers)->deleteJson($url)->assertStatus(500);
        $this->assertDatabaseHas('properties',['id'=>$property->id]);
        $this->assertDatabaseHas('listing_videos',['id'=>$video->id]);
        $storage->fail=false;
        $this->withHeaders($headers)->deleteJson($url)->assertOk();
        $this->assertDatabaseMissing('properties',['id'=>$property->id]);
        $this->assertDatabaseCount('listing_videos',0);
        Storage::disk('local')->assertMissing($video->original_path);
        Storage::disk('local')->assertMissing($partial);
    }


}
