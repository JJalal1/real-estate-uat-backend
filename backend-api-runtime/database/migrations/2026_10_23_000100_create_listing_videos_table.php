<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('listing_videos', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_id')->constrained('properties')->cascadeOnDelete();
            $table->uuid('upload_id');
            $table->string('status', 24)->default('uploading');
            // The listing reviewer must explicitly approve the video as well.
            $table->string('moderation_status', 20)->default('pending');
            $table->timestamp('moderated_at')->nullable();
            $table->foreignId('moderated_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->index('moderated_by_user_id');
            $table->string('original_path', 500);
            // Track superseded originals until provider deletion is acknowledged.
            $table->json('cleanup_paths')->nullable();
            $table->string('playback_path', 500)->nullable();
            $table->unsignedBigInteger('playback_size_bytes')->nullable();
            $table->string('poster_path', 500)->nullable();
            $table->string('mime_type', 80);
            $table->unsignedBigInteger('size_bytes');
            $table->char('content_sha256', 64);
            $table->unsignedInteger('duration_ms')->nullable();
            $table->unsignedInteger('width')->nullable();
            $table->unsignedInteger('height')->nullable();
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->string('failure_code', 64)->nullable();
            $table->timestamp('processed_at')->nullable();
            $table->timestamps();
            $table->unique(['property_id', 'upload_id'], 'listing_videos_property_upload_unique');
            $table->unique('property_id', 'listing_videos_one_per_property_unique');
            $table->index(['property_id', 'status'], 'listing_videos_property_status_idx');
            $table->index(['status', 'created_at'], 'listing_videos_processing_idx');
        });

        // Shared, database-backed health signal from the *isolated* worker.
        // No browser/mobile roles may read or forge a heartbeat.
        Schema::create('listing_video_worker_health', function (Blueprint $table): void {
            $table->unsignedInteger('id')->primary();
            $table->timestamp('last_seen_at');
        });

        // Laravel alone owns authorization; never publish the private original
        // or processed video record through Supabase's direct Data API.
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE public.listing_video_worker_health ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.listing_video_worker_health FROM PUBLIC, anon, authenticated');
            DB::statement('ALTER TABLE public.listing_videos ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.listing_videos FROM PUBLIC, anon, authenticated');
            DB::statement('REVOKE ALL ON SEQUENCE public.listing_videos_id_seq FROM PUBLIC, anon, authenticated');
            DB::statement("ALTER TABLE public.listing_videos ADD CONSTRAINT listing_videos_status_check CHECK (status IN ('uploading','upload_failed','uploaded','processing','ready','failed'))");
            DB::statement("ALTER TABLE public.listing_videos ADD CONSTRAINT listing_videos_moderation_check CHECK (moderation_status IN ('pending','approved'))");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('listing_video_worker_health');
        Schema::dropIfExists('listing_videos');
    }
};
