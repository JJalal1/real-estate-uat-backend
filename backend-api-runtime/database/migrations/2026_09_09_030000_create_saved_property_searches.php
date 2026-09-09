<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('saved_property_searches', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->json('filters');
            $table->string('fingerprint', 64);
            $table->string('alert_frequency', 16)->default('instant');
            $table->boolean('is_active')->default(true);
            $table->unsignedBigInteger('last_match_property_id')->nullable();
            $table->timestamp('last_checked_at')->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'fingerprint'], 'saved_property_searches_user_filter_unique');
            $table->index(['is_active', 'alert_frequency'], 'saved_property_searches_alert_index');
            $table->index(['user_id', 'updated_at'], 'saved_property_searches_user_updated_index');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE public.saved_property_searches ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.saved_property_searches FROM PUBLIC');
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN EXECUTE 'REVOKE ALL ON TABLE public.saved_property_searches FROM anon'; END IF; END $$");
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE public.saved_property_searches FROM authenticated'; END IF; END $$");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('saved_property_searches');
    }
};
