<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Carbon;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('users', fn (Blueprint $table) => $table->unsignedBigInteger('draft_restart_us')->nullable());
        Schema::table('listing_editor_drafts', function (Blueprint $table): void {
            $table->unsignedBigInteger('first_saved_us')->nullable();
            $table->index('created_at');
        });
        Schema::table('properties', fn (Blueprint $table) => $table->timestampTz('draft_expires_at')->nullable()->index());

        DB::table('properties')->where('status', 'draft')->where('review_status', 'draft')
            ->whereNull('first_listed_at')->whereNull('submitted_at')->whereNull('reviewed_at')->whereNull('published_at')
            ->whereNotIn('id', DB::table('listing_reviews')->select('listing_id'))
            ->select('id', 'created_at')->addSelect(['checkpoint_created_at' => DB::table('listing_editor_drafts')
                ->selectRaw('MIN(created_at)')->whereColumn('property_id', 'properties.id')])
            ->chunkById(200, function ($rows): void {
                foreach ($rows as $row) {
                    $created = Carbon::parse($row->created_at);
                    if ($row->checkpoint_created_at) $created = $created->min(Carbon::parse($row->checkpoint_created_at));
                    DB::table('properties')->where('id', $row->id)->update(['draft_expires_at' => $created->addDays(7)]);
                }
            });
    }

    public function down(): void
    {
        Schema::table('properties', function (Blueprint $table): void {
            $table->dropIndex(['draft_expires_at']);
            $table->dropColumn('draft_expires_at');
        });
        Schema::table('listing_editor_drafts', function (Blueprint $table): void {
            $table->dropIndex(['created_at']);
            $table->dropColumn('first_saved_us');
        });
        Schema::table('users', fn (Blueprint $table) => $table->dropColumn('draft_restart_us'));
    }
};
