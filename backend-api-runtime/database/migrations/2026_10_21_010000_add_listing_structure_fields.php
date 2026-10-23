<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->unsignedSmallInteger('floors_count')->nullable();
            $table->json('units_per_floor')->nullable();
            $table->unsignedSmallInteger('shop_openings')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('properties', fn (Blueprint $table) => $table->dropColumn(['floors_count','units_per_floor','shop_openings']));
    }
};
