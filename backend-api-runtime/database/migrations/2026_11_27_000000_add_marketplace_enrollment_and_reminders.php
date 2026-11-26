<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->timestampTz('broker_enrolled_at')->nullable();
            $table->string('marketplace_governorate', 120)->nullable();
            $table->boolean('marketplace_is_office')->nullable();
            $table->string('marketplace_office_name', 140)->nullable();
        });
        Schema::table('properties', function (Blueprint $table): void {
            $table->timestampTz('first_listed_at')->nullable();
        });
        Schema::table('property_platform_receivables', function (Blueprint $table): void {
            $table->timestampTz('last_reminded_at')->nullable();
        });
        DB::table('properties')->where(fn ($q) => $q->where('status', 'published')->orWhereNotNull('published_at')->orWhereNotNull('submitted_at')
            ->orWhereIn('id', DB::table('listing_reviews')->whereIn('action', ['submitted', 'approved'])->select('listing_id')))
            ->update(['first_listed_at' => DB::raw('COALESCE(submitted_at, published_at, created_at)')]);
        DB::table('properties')->where('financial_hold_reason', 'platform_receivable_overdue')
            ->update(['financial_hold_at' => null, 'financial_hold_reason' => null]);
        DB::table('property_financial_holds')->where('reason', 'platform_receivable_open')
            ->whereNull('released_at')->update(['released_at' => now(), 'release_reason' => 'marketplace_reminders', 'updated_at' => now()]);
    }

    public function down(): void
    {
        Schema::table('property_platform_receivables', fn (Blueprint $table) => $table->dropColumn('last_reminded_at'));
        Schema::table('properties', fn (Blueprint $table) => $table->dropColumn('first_listed_at'));
        Schema::table('users', fn (Blueprint $table) => $table->dropColumn(['broker_enrolled_at', 'marketplace_governorate', 'marketplace_is_office', 'marketplace_office_name']));
    }
};
