<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        // Intentionally not a foreign key. Deleting a listing does not reset publishing history.
        Schema::table('users', fn (Blueprint $table) => $table->unsignedBigInteger('first_marketplace_listing_id')->nullable());
        DB::statement("UPDATE users SET first_marketplace_listing_id = COALESCE(
            (SELECT MIN(p.id) FROM properties p WHERE p.user_id = users.id AND p.first_listed_at IS NOT NULL),
            (SELECT MIN(a.subject_id) FROM audit_logs a WHERE a.target_user_id = users.id
                AND a.subject_type = 'Property' AND a.action IN ('listing.submitted','listing.approved'))
        )");
    }

    public function down(): void
    {
        Schema::table('users', fn (Blueprint $table) => $table->dropColumn('first_marketplace_listing_id'));
    }
};
