<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('property_payment_methods', function (Blueprint $table): void {
            $table->boolean('allows_full_payment')->default(true)->after('max_amount');
            $table->boolean('allows_sai_only')->default(true)->after('allows_full_payment');
        });
    }

    public function down(): void
    {
        Schema::table('property_payment_methods', function (Blueprint $table): void {
            $table->dropColumn(['allows_full_payment', 'allows_sai_only']);
        });
    }
};
