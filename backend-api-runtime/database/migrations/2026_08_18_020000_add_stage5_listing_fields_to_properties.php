<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        $addOwnerKey = ! Schema::hasColumn('properties', 'owner_key');
        $addPhone = ! Schema::hasColumn('properties', 'contact_phone');
        $addWhatsapp = ! Schema::hasColumn('properties', 'contact_whatsapp');

        Schema::table('properties', function (Blueprint $table) use (
            $addOwnerKey,
            $addPhone,
            $addWhatsapp,
        ) {
            if ($addOwnerKey) {
                $table->string('owner_key', 96)->nullable()->index();
            }
            if ($addPhone) {
                $table->string('contact_phone', 32)->nullable();
            }
            if ($addWhatsapp) {
                $table->string('contact_whatsapp', 32)->nullable();
            }
        });
    }

    public function down(): void
    {
        $dropWhatsapp = Schema::hasColumn('properties', 'contact_whatsapp');
        $dropPhone = Schema::hasColumn('properties', 'contact_phone');
        $dropOwnerKey = Schema::hasColumn('properties', 'owner_key');

        Schema::table('properties', function (Blueprint $table) use (
            $dropWhatsapp,
            $dropPhone,
            $dropOwnerKey,
        ) {
            if ($dropWhatsapp) {
                $table->dropColumn('contact_whatsapp');
            }
            if ($dropPhone) {
                $table->dropColumn('contact_phone');
            }
            if ($dropOwnerKey) {
                $table->dropColumn('owner_key');
            }
        });
    }
};
