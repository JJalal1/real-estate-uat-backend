<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            if (! Schema::hasColumn('properties', 'has_garden')) {
                $table->boolean('has_garden')->nullable()->after('has_parking');
            }
        });
    }

    public function down(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            if (Schema::hasColumn('properties', 'has_garden')) {
                $table->dropColumn('has_garden');
            }
        });
    }
};
