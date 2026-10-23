<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->boolean('has_elevator')->nullable();
            // Editorial visibility foundation only; no plan, price or payment.
            $table->timestampTz('spotlight_until')->nullable()->index();
        });
    }

    public function down(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->dropIndex(['spotlight_until']);
            $table->dropColumn(['has_elevator', 'spotlight_until']);
        });
    }
};
