<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('broker_deal_outcomes', function (Blueprint $table): void {
            $table->unsignedInteger('advertiser_attention_revision')->default(0);
            $table->unsignedInteger('advertiser_seen_revision')->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('broker_deal_outcomes', function (Blueprint $table): void {
            $table->dropColumn(['advertiser_attention_revision', 'advertiser_seen_revision']);
        });
    }
};
