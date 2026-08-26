<?php

use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('phone', 32)->nullable()->unique()->after('email_verified_at');
            $table->timestamp('phone_verified_at')->nullable()->after('phone');
            $table->string('account_status', 32)->default(User::STATUS_ACTIVE)->index()->after('password');
            $table->timestamp('last_login_at')->nullable()->after('account_status');
        });

        DB::table('users')->whereNull('account_status')->update(['account_status'=>User::STATUS_ACTIVE]);
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['phone','phone_verified_at','account_status','last_login_at']);
        });
    }
};
