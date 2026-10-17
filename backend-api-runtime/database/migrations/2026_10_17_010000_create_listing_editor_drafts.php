<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('listing_editor_drafts', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->uuid('client_key');
            $table->foreignId('property_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedInteger('revision')->default(0);
            $table->json('payload'); $table->json('images'); $table->timestamps();
            $table->unique(['user_id','client_key']); $table->index(['user_id','updated_at']);
        });
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE listing_editor_drafts ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON listing_editor_drafts FROM PUBLIC');
            foreach (['anon','authenticated'] as $role) {
                if (DB::select('SELECT 1 FROM pg_roles WHERE rolname = ?', [$role])) {
                    DB::statement('REVOKE ALL ON listing_editor_drafts FROM '.$role);
                    DB::statement('REVOKE ALL ON SEQUENCE listing_editor_drafts_id_seq FROM '.$role);
                }
            }
        }
    }
    public function down(): void { Schema::dropIfExists('listing_editor_drafts'); }
};
