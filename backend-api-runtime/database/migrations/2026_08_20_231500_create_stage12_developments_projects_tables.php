<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('developers', function (Blueprint $table): void {
            $table->id();
            $table->string('name', 160);
            $table->string('slug', 160)->unique();
            $table->text('description')->nullable();
            $table->string('website', 500)->nullable();
            $table->string('phone', 40)->nullable();
            $table->string('email', 190)->nullable();
            $table->string('logo_url', 500)->nullable();
            $table->string('status', 24)->default('active')->index();
            $table->unsignedBigInteger('created_by_user_id')->nullable()->index();
            $table->string('created_by_name_snapshot', 120)->nullable();
            $table->timestamps();
        });

        Schema::create('developments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('developer_id')->constrained('developers')->restrictOnDelete();
            $table->unsignedBigInteger('created_by_user_id')->nullable()->index();
            $table->string('created_by_name_snapshot', 120)->nullable();
            $table->string('name', 180);
            $table->string('slug', 180)->unique();
            $table->text('description')->nullable();
            $table->string('status', 24)->default('draft')->index();
            $table->string('completion_status', 32)->default('planned')->index();
            $table->date('expected_completion_date')->nullable();
            $table->foreignId('governorate_id')->nullable()->constrained('governorates')->nullOnDelete();
            $table->foreignId('geo_cell_id')->nullable()->constrained('geo_cells')->nullOnDelete();
            $table->string('address', 500)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('cover_image_url', 500)->nullable();
            $table->unsignedBigInteger('published_by_user_id')->nullable()->index();
            $table->string('published_by_name_snapshot', 120)->nullable();
            $table->timestampTz('published_at')->nullable()->index();
            $table->timestamps();
            $table->index(['developer_id','status','created_at'], 'developments_developer_status_idx');
            $table->index(['governorate_id','status'], 'developments_governorate_status_idx');
            $table->index(['geo_cell_id','status'], 'developments_cell_status_idx');
        });

        Schema::create('development_units', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('development_id')->constrained('developments')->cascadeOnDelete();
            $table->string('code', 80);
            $table->string('title', 180);
            $table->string('unit_type', 40)->index();
            $table->string('floor_label', 80)->nullable();
            $table->unsignedSmallInteger('bedrooms')->nullable();
            $table->decimal('bathrooms', 4, 1)->nullable();
            $table->decimal('area_m2', 12, 2);
            $table->decimal('price', 18, 2)->nullable();
            $table->string('currency', 8)->default('YER');
            $table->string('status', 24)->default('available')->index();
            $table->date('available_from')->nullable();
            $table->text('description')->nullable();
            $table->timestamps();
            $table->unique(['development_id','code'], 'development_units_project_code_unique');
            $table->index(['development_id','status'], 'development_units_project_status_idx');
        });

        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("ALTER TABLE developers ADD CONSTRAINT developers_status_check CHECK (status IN ('active','inactive'))");
            DB::statement("ALTER TABLE developments ADD CONSTRAINT developments_status_check CHECK (status IN ('draft','published','archived'))");
            DB::statement("ALTER TABLE developments ADD CONSTRAINT developments_completion_status_check CHECK (completion_status IN ('planned','under_construction','completed'))");
            DB::statement('ALTER TABLE developments ADD CONSTRAINT developments_latitude_check CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90)');
            DB::statement('ALTER TABLE developments ADD CONSTRAINT developments_longitude_check CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)');
            DB::statement("ALTER TABLE development_units ADD CONSTRAINT development_units_status_check CHECK (status IN ('available','reserved','sold','hidden'))");
            DB::statement('ALTER TABLE development_units ADD CONSTRAINT development_units_area_check CHECK (area_m2 > 0)');
            DB::statement('ALTER TABLE development_units ADD CONSTRAINT development_units_price_check CHECK (price IS NULL OR price >= 0)');
        }

        $now=now();
        $permissions=[
            ['key'=>'developments.manage','name_ar'=>'إدارة المطورين والمشاريع والوحدات','name_en'=>'Manage developers, projects and units','scope'=>'developments'],
            ['key'=>'developments.publish','name_ar'=>'نشر وإلغاء نشر المشاريع العقارية','name_en'=>'Publish and unpublish developments','scope'=>'developments'],
        ];
        foreach($permissions as $permission){
            DB::table('permissions')->updateOrInsert(['key'=>$permission['key']],$permission+['created_at'=>$now,'updated_at'=>$now]);
        }
        $permissionIds=DB::table('permissions')->whereIn('key',['developments.manage','developments.publish'])->pluck('id','key');
        $roleIds=DB::table('roles')->whereIn('key',['regions_manager','content_moderator'])->pluck('id','key');
        $map=[
            'regions_manager'=>['developments.manage'],
            'content_moderator'=>['developments.manage','developments.publish'],
        ];
        foreach($map as $roleKey=>$keys){
            if(!isset($roleIds[$roleKey])) continue;
            foreach($keys as $key){
                if(!isset($permissionIds[$key])) continue;
                DB::table('role_permission')->insertOrIgnore(['role_id'=>$roleIds[$roleKey],'permission_id'=>$permissionIds[$key]]);
            }
        }
    }

    public function down(): void
    {
        $permissionIds=DB::table('permissions')->whereIn('key',['developments.manage','developments.publish'])->pluck('id');
        if($permissionIds->isNotEmpty()) DB::table('role_permission')->whereIn('permission_id',$permissionIds)->delete();
        DB::table('permissions')->whereIn('key',['developments.manage','developments.publish'])->delete();
        Schema::dropIfExists('development_units');
        Schema::dropIfExists('developments');
        Schema::dropIfExists('developers');
    }
};
