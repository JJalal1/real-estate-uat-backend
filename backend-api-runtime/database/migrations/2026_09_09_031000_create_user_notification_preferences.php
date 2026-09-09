<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('user_notification_preferences', function (Blueprint $table): void {
            $table->foreignId('user_id')->primary()->constrained()->cascadeOnDelete();
            $table->boolean('messages')->default(true);
            $table->boolean('viewings')->default(true);
            $table->boolean('agreements')->default(true);
            $table->boolean('listing_activity')->default(true);
            $table->boolean('discovery_alerts')->default(true);
            $table->boolean('services')->default(true);
            $table->timestamps();
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.user_notification_preferences FROM PUBLIC');
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN EXECUTE 'REVOKE ALL ON TABLE public.user_notification_preferences FROM anon'; END IF; END $$");
            DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN EXECUTE 'REVOKE ALL ON TABLE public.user_notification_preferences FROM authenticated'; END IF; END $$");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('user_notification_preferences');
    }
};
