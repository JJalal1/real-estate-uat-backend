<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->foreignId('review_assigned_to_user_id')
                ->nullable()
                ->after('review_status')
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('review_assigned_at')->nullable()->after('review_assigned_to_user_id');
            $table->index(
                ['review_status', 'review_assigned_to_user_id'],
                'properties_review_assignment_idx'
            );
        });
    }

    public function down(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->dropIndex('properties_review_assignment_idx');
            $table->dropConstrainedForeignId('review_assigned_to_user_id');
            $table->dropColumn('review_assigned_at');
        });
    }
};
