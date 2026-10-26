<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('listing_image_upload_intents', function (Blueprint $table): void {
            $table->id();
            // Preserve a cleanup tombstone if a user/draft is erased. A
            // cascading delete here would leak a TUS original in Storage.
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('listing_editor_draft_id')->nullable()->constrained('listing_editor_drafts')->nullOnDelete();
            $table->uuid('image_key');
            $table->string('path', 255)->unique();
            $table->char('sha256', 64);
            $table->unsignedInteger('byte_length');
            $table->string('mime', 32);
            $table->string('status', 16)->default('pending');
            $table->timestamp('signed_until');
            // TUS session URLs last up to 24 hours. Keep objects quarantined
            // until all possible PATCH retries have expired, then purge.
            $table->timestamp('purge_after');
            $table->timestamps();
            // PostgreSQL does not index referencing columns automatically.
            // Cover account erasure's SET NULL lookup without a table scan.
            $table->index('user_id');
            $table->unique(['listing_editor_draft_id', 'image_key'], 'listing_image_intent_draft_key_unique');
            $table->index(['status', 'purge_after']);
        });
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE listing_image_upload_intents ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON listing_image_upload_intents FROM PUBLIC');
            DB::statement('REVOKE ALL ON SEQUENCE listing_image_upload_intents_id_seq FROM PUBLIC');
            foreach (['anon', 'authenticated'] as $role) {
                if (DB::select('SELECT 1 FROM pg_roles WHERE rolname = ?', [$role])) {
                    DB::statement('REVOKE ALL ON listing_image_upload_intents FROM '.$role);
                    DB::statement('REVOKE ALL ON SEQUENCE listing_image_upload_intents_id_seq FROM '.$role);
                }
            }
        }
    }
    public function down(): void { Schema::dropIfExists('listing_image_upload_intents'); }
};

