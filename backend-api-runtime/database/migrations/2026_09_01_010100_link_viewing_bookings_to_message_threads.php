<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('viewing_bookings', function (Blueprint $table): void {
            $table->foreignId('message_thread_id')
                ->nullable()
                ->after('host_name_snapshot')
                ->constrained('message_threads')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('viewing_bookings', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('message_thread_id');
        });
    }
};
