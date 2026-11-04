<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('user_push_devices', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->string('platform', 20);
            $table->text('token');
            $table->char('token_hash', 64)->unique();
            $table->char('installation_hash', 64);
            $table->unsignedInteger('app_build')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('disabled_at')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'installation_hash'], 'push_devices_user_installation_unique');
            $table->index(['user_id', 'disabled_at'], 'push_devices_user_active_index');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE public.user_push_devices ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON TABLE public.user_push_devices FROM PUBLIC');
            DB::statement('REVOKE ALL ON SEQUENCE public.user_push_devices_id_seq FROM PUBLIC');
            DB::statement('REVOKE ALL ON TABLE public.user_push_devices FROM anon, authenticated');
            DB::statement('REVOKE ALL ON SEQUENCE public.user_push_devices_id_seq FROM anon, authenticated');
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('user_push_devices');
    }
};
