<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('private_messages', function (Blueprint $table): void {
            $table->string('client_message_id', 100)->nullable()->after('sender_name_snapshot');
            $table->unique(
                ['thread_id', 'sender_user_id', 'client_message_id'],
                'private_messages_sender_client_unique',
            );
        });
    }

    public function down(): void
    {
        Schema::table('private_messages', function (Blueprint $table): void {
            $table->dropUnique('private_messages_sender_client_unique');
            $table->dropColumn('client_message_id');
        });
    }
};
