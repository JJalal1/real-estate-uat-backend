<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $driver = DB::connection()->getDriverName();

        if (! Schema::hasColumn('listing_reviews', 'actor_name_snapshot')) {
            Schema::table('listing_reviews', function ($table): void {
                $table->string('actor_name_snapshot', 120)->nullable()->after('actor_user_id');
            });
        }

        if ($driver === 'pgsql') {
            $fk = DB::selectOne("
                SELECT conname
                FROM pg_constraint
                WHERE conrelid = 'listing_reviews'::regclass
                  AND contype = 'f'
                  AND conname = 'listing_reviews_actor_user_id_foreign'
                LIMIT 1
            ");

            if ($fk) {
                DB::unprepared('DROP TRIGGER IF EXISTS listing_reviews_immutable_update ON listing_reviews');
                DB::statement("
                    UPDATE listing_reviews lr
                    SET actor_name_snapshot = u.name
                    FROM users u
                    WHERE lr.actor_user_id = u.id
                      AND lr.actor_name_snapshot IS NULL
                ");
                DB::unprepared("
                    CREATE TRIGGER listing_reviews_immutable_update
                    BEFORE UPDATE ON listing_reviews
                    FOR EACH ROW EXECUTE FUNCTION prevent_stage9_listing_review_mutation()
                ");
                DB::statement('ALTER TABLE listing_reviews DROP CONSTRAINT listing_reviews_actor_user_id_foreign');
            }
        }
    }

    public function down(): void
    {
        // Intentionally non-destructive. Restoring the deleted-user FK would make
        // immutable history incompatible with account deletion again.
    }
};
