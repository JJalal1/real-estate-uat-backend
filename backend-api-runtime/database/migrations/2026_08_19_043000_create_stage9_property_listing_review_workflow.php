<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('property_assets', function(Blueprint $table): void {
            $table->id();$table->foreignId('created_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('identity_hash',64)->unique();$table->unsignedSmallInteger('identity_version')->default(1);
            $table->string('property_type',40);$table->string('canonical_address')->nullable();
            $table->decimal('canonical_latitude',10,7);$table->decimal('canonical_longitude',10,7);
            $table->unsignedInteger('area_m2')->nullable();$table->unsignedSmallInteger('bedrooms')->nullable();$table->unsignedSmallInteger('bathrooms')->nullable();
            $table->text('identity_notes')->nullable();$table->string('status',30)->default('active')->index();$table->timestamps();
        });

        Schema::table('properties', function(Blueprint $table): void {
            $table->foreignId('property_asset_id')->nullable()->after('user_id')->constrained('property_assets')->restrictOnDelete();
            $table->string('review_status',40)->default('draft')->index();$table->timestamp('submitted_at')->nullable();
            $table->timestamp('published_at')->nullable();$table->timestamp('reviewed_at')->nullable();$table->text('last_review_reason')->nullable();
            $table->index(['property_asset_id','purpose'],'properties_asset_purpose_idx');
        });

        Schema::create('listing_documents', function(Blueprint $table): void {
            $table->id();$table->foreignId('property_id')->constrained('properties')->cascadeOnDelete();
            $table->foreignId('uploaded_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('kind',60)->default('ownership_or_authorization');$table->string('path',500);$table->string('original_name',255);
            $table->string('mime_type',120)->nullable();$table->unsignedBigInteger('size_bytes')->default(0);$table->timestamp('created_at')->useCurrent();
        });

        Schema::create('listing_reviews', function(Blueprint $table): void {
            $table->id();$table->unsignedBigInteger('listing_id')->nullable()->index();$table->unsignedBigInteger('actor_user_id')->nullable()->index();$table->string('actor_name_snapshot',120)->nullable();
            $table->string('action',80)->index();$table->string('from_review_status',40)->nullable();$table->string('to_review_status',40)->nullable();
            $table->text('reason')->nullable();$table->json('listing_snapshot')->nullable();$table->json('metadata')->nullable();$table->timestamp('created_at')->useCurrent()->index();
        });

        Schema::create('property_publication_blocks', function(Blueprint $table): void {
            $table->id();$table->foreignId('property_asset_id')->constrained('property_assets')->restrictOnDelete();$table->string('purpose',20);
            $table->boolean('is_active')->default(true)->index();$table->text('reason');$table->foreignId('blocked_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->unsignedBigInteger('source_listing_id')->nullable();$table->timestamp('blocked_at')->useCurrent();
            $table->foreignId('lifted_by_user_id')->nullable()->constrained('users')->nullOnDelete();$table->text('lifted_reason')->nullable();$table->timestamp('lifted_at')->nullable();$table->timestamps();
            $table->index(['property_asset_id','purpose','is_active'],'property_publication_blocks_lookup_idx');
        });

        $fingerprint=function($row): string {
            $address=Str::lower(trim(preg_replace('/\\s+/u',' ',(string)($row->address??''))??''));
            $parts=['v1',Str::lower((string)$row->type),number_format((float)$row->latitude,6,'.',''),number_format((float)$row->longitude,6,'.',''),(string)($row->area_m2??''),(string)($row->bedrooms??''),(string)($row->bathrooms??''),$address];
            return hash('sha256',implode('|',$parts));
        };
        foreach(DB::table('properties')->orderBy('id')->get() as $row){
            $hash=$fingerprint($row);$assetId=DB::table('property_assets')->where('identity_hash',$hash)->value('id');
            if(!$assetId){$assetId=DB::table('property_assets')->insertGetId(['created_by_user_id'=>$row->user_id,'identity_hash'=>$hash,'identity_version'=>1,'property_type'=>$row->type,'canonical_address'=>$row->address,'canonical_latitude'=>$row->latitude,'canonical_longitude'=>$row->longitude,'area_m2'=>$row->area_m2,'bedrooms'=>$row->bedrooms,'bathrooms'=>$row->bathrooms,'status'=>'active','created_at'=>now(),'updated_at'=>now()]);}
            $reviewStatus=match((string)$row->status){'published'=>'approved','pending'=>'submitted','draft'=>'draft','rejected'=>'legacy_rejected','archived'=>'archived',default=>'draft'};
            DB::table('properties')->where('id',$row->id)->update(['property_asset_id'=>$assetId,'review_status'=>$reviewStatus,'published_at'=>$row->status==='published'?($row->updated_at??$row->created_at??now()):null,'submitted_at'=>$row->status==='pending'?($row->updated_at??now()):null]);
            if($row->status==='published') DB::table('listing_reviews')->insert(['listing_id'=>$row->id,'actor_user_id'=>null,'action'=>'legacy_stage8_import_approved','from_review_status'=>null,'to_review_status'=>'approved','reason'=>'Existing Stage 8 publication grandfathered during Stage 9 migration. Future edits require review.','listing_snapshot'=>json_encode(['id'=>$row->id,'user_id'=>$row->user_id,'property_asset_id'=>$assetId,'title'=>$row->title,'purpose'=>$row->purpose,'status'=>'published','review_status'=>'approved']),'metadata'=>json_encode(['legacy_import'=>true]),'created_at'=>now()]);
        }

        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){
            DB::unprepared("CREATE UNIQUE INDEX property_publication_blocks_one_active ON property_publication_blocks(property_asset_id,purpose) WHERE is_active=true");
            DB::unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION prevent_stage9_listing_review_mutation() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'listing_reviews are immutable'; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER listing_reviews_immutable_update BEFORE UPDATE ON listing_reviews FOR EACH ROW EXECUTE FUNCTION prevent_stage9_listing_review_mutation();
CREATE TRIGGER listing_reviews_immutable_delete BEFORE DELETE ON listing_reviews FOR EACH ROW EXECUTE FUNCTION prevent_stage9_listing_review_mutation();
SQL);
        }elseif($driver==='sqlite'){
            DB::unprepared('CREATE UNIQUE INDEX property_publication_blocks_one_active ON property_publication_blocks(property_asset_id,purpose) WHERE is_active = 1');
            DB::unprepared("CREATE TRIGGER listing_reviews_immutable_update BEFORE UPDATE ON listing_reviews BEGIN SELECT RAISE(ABORT, 'listing_reviews are immutable'); END;");
            DB::unprepared("CREATE TRIGGER listing_reviews_immutable_delete BEFORE DELETE ON listing_reviews BEGIN SELECT RAISE(ABORT, 'listing_reviews are immutable'); END;");
        }
    }

    public function down(): void
    {
        $driver=DB::connection()->getDriverName();
        if($driver==='pgsql'){DB::unprepared('DROP TRIGGER IF EXISTS listing_reviews_immutable_update ON listing_reviews');DB::unprepared('DROP TRIGGER IF EXISTS listing_reviews_immutable_delete ON listing_reviews');DB::unprepared('DROP FUNCTION IF EXISTS prevent_stage9_listing_review_mutation()');DB::unprepared('DROP INDEX IF EXISTS property_publication_blocks_one_active');}
        elseif($driver==='sqlite'){DB::unprepared('DROP TRIGGER IF EXISTS listing_reviews_immutable_update');DB::unprepared('DROP TRIGGER IF EXISTS listing_reviews_immutable_delete');DB::unprepared('DROP INDEX IF EXISTS property_publication_blocks_one_active');}
        Schema::dropIfExists('property_publication_blocks');Schema::dropIfExists('listing_reviews');Schema::dropIfExists('listing_documents');
        Schema::table('properties',function(Blueprint $table):void{$table->dropIndex('properties_asset_purpose_idx');$table->dropConstrainedForeignId('property_asset_id');$table->dropColumn(['review_status','submitted_at','published_at','reviewed_at','last_review_reason']);});
        Schema::dropIfExists('property_assets');
    }
};
