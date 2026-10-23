<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('properties', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->text('description')->nullable();
            $table->enum('purpose', ['sale', 'rent']);
            $table->enum('type', ['apartment', 'house', 'villa', 'land', 'shop', 'office', 'farm']);
            $table->decimal('price', 15, 2);
            $table->string('currency', 3)->default('USD');
            $table->unsignedInteger('area_m2')->nullable();
            $table->unsignedSmallInteger('bedrooms')->nullable();
            $table->unsignedSmallInteger('bathrooms')->nullable();
            $table->string('address')->nullable();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->enum('status', ['draft', 'pending', 'published', 'rejected', 'archived'])->default('pending');
            $table->timestamps();
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE properties ADD COLUMN location geography(Point, 4326)');
            DB::statement("UPDATE properties SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography");
            DB::statement('CREATE INDEX properties_location_gix ON properties USING GIST (location)');
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('properties');
    }
};
