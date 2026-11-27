<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->unsignedSmallInteger('parking_spaces')->nullable();
            $table->boolean('has_separate_majlis')->nullable();
            $table->boolean('has_majlis_bathroom')->nullable();
            $table->string('land_use', 20)->nullable();
            $table->decimal('street_width_m', 6, 2)->nullable();
            $table->boolean('has_yard')->nullable();
            $table->unsignedSmallInteger('office_rooms')->nullable();
            $table->string('farm_water_source', 20)->nullable();
            $table->string('farm_crop_type', 20)->nullable();
            $table->boolean('section_elevator')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('properties', fn (Blueprint $table) => $table->dropColumn([
            'parking_spaces', 'has_separate_majlis', 'has_majlis_bathroom', 'land_use',
            'street_width_m', 'has_yard', 'office_rooms', 'farm_water_source', 'farm_crop_type',
            'section_elevator',
        ]));
    }
};
