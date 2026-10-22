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
            $table->string('status', 24)->default('uploaded');
            $table->string('original_path', 500);
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
            $table->index(['property_id', 'status'], 'listing_videos_property_status_idx');
            $table->index(['status', 'created_at'], 'listing_videos_processing_idx');
        });

        // Laravel alone owns authorization; never publish the private original
        // or processed video record through Supabase's direct Data API.
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE public.listing_videos ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.listing_videos FROM PUBLIC, anon, authenticated');
            DB::statement('REVOKE ALL ON SEQUENCE public.listing_videos_id_seq FROM PUBLIC, anon, authenticated');
            DB::statement("ALTER TABLE public.listing_videos ADD CONSTRAINT listing_videos_status_check CHECK (status IN ('uploaded','processing','ready','failed'))");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('listing_videos');
    }
};
