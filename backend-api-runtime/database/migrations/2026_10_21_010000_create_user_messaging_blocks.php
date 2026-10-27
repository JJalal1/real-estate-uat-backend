<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('user_messaging_blocks',function(Blueprint $table):void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->restrictOnDelete();
            $table->foreignId('blocked_user_id')->constrained('users')->restrictOnDelete();
            $table->timestamps();
            $table->unique(['user_id','blocked_user_id']);
            $table->index(['blocked_user_id','user_id']);
        });
        if (DB::getDriverName()==='pgsql') {
            DB::statement('ALTER TABLE user_messaging_blocks ADD CONSTRAINT messaging_blocks_not_self CHECK (user_id <> blocked_user_id)');
            DB::statement('ALTER TABLE user_messaging_blocks ENABLE ROW LEVEL SECURITY');
            DB::statement('REVOKE ALL ON user_messaging_blocks FROM PUBLIC');
            DB::statement('REVOKE ALL ON SEQUENCE user_messaging_blocks_id_seq FROM PUBLIC');
            foreach (['anon','authenticated'] as $role) if (DB::select('SELECT 1 FROM pg_roles WHERE rolname = ?',[$role])) {
                DB::statement('REVOKE ALL ON user_messaging_blocks FROM '.$role);
                DB::statement('REVOKE ALL ON SEQUENCE user_messaging_blocks_id_seq FROM '.$role);
            }
        }
    }
    public function down():void { Schema::dropIfExists('user_messaging_blocks'); }
};
