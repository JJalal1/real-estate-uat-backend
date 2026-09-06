<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('property_requests', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('requester_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('operation_type', 16);
            $table->string('property_type', 32);
            $table->string('governorate', 120);
            $table->string('district', 120)->nullable();
            $table->string('area', 160)->nullable();
            $table->decimal('budget_min', 15, 2);
            $table->decimal('budget_max', 15, 2);
            $table->string('currency', 3)->default('YER');
            $table->unsignedInteger('requested_area_min')->nullable();
            $table->unsignedInteger('requested_area_max')->nullable();
            $table->unsignedSmallInteger('rooms')->nullable();
            $table->text('additional_specifications')->nullable();
            $table->unsignedSmallInteger('active_duration_days');
            $table->string('status', 16)->default('active');
            $table->timestampTz('expires_at')->index();
            $table->timestampTz('matched_at')->nullable();
            $table->timestampTz('closed_at')->nullable();
            $table->timestampTz('expired_at')->nullable();
            $table->timestamps();
            $table->index(['requester_user_id', 'status', 'id']);
            $table->index(['status', 'operation_type', 'property_type', 'governorate'], 'property_requests_matching_idx');
        });

        Schema::create('property_suggestions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('property_request_id')->constrained('property_requests')->cascadeOnDelete();
            $table->foreignId('property_id')->constrained('properties')->restrictOnDelete();
            $table->foreignId('suggested_by_user_id')->constrained('users')->restrictOnDelete();
            $table->string('suggested_by_name_snapshot', 120);
            $table->text('note')->nullable();
            $table->timestampTz('viewed_at')->nullable();
            $table->timestamps();
            $table->unique(['property_request_id', 'property_id'], 'property_request_property_suggestion_unique');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("ALTER TABLE property_requests ADD CONSTRAINT property_requests_operation_check CHECK (operation_type IN ('sale','rent'))");
            DB::statement("ALTER TABLE property_requests ADD CONSTRAINT property_requests_status_check CHECK (status IN ('active','matched','closed','expired'))");
            DB::statement('ALTER TABLE property_requests ADD CONSTRAINT property_requests_budget_check CHECK (budget_min >= 0 AND budget_max >= budget_min)');
            DB::statement('ALTER TABLE property_requests ADD CONSTRAINT property_requests_area_check CHECK (requested_area_min IS NULL OR requested_area_max IS NULL OR requested_area_max >= requested_area_min)');
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('property_suggestions');
        Schema::dropIfExists('property_requests');
    }
};
