from pathlib import Path
import re


def replace_regex(path: str, pattern: str, replacement: str) -> None:
    p = Path(path)
    text = p.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected exactly one regex match in {path}, found {count}")
    p.write_text(updated)


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one match in {path}, found {count}")
    p.write_text(text.replace(old, new, 1))


service = "backend-api-runtime/app/Services/PropertyIdentityService.php"
replace_regex(
    service,
    r"    public function ensureRepresentation\(Property \$listing\): void\n    \{.*?\n    \}\n\n    public function transferRepresentation",
    """    public function ensureRepresentation(Property $listing): void
    {
        DB::transaction(function () use ($listing): void {
            $existing = DB::table('property_representation_claims')
                ->where('property_asset_id', $listing->property_asset_id)
                ->where('status', 'active')
                ->lockForUpdate()
                ->first();
            if ($existing) {
                if ((int) $existing->advertiser_user_id !== (int) $listing->user_id) {
                    throw new ConflictHttpException('يوجد ممثل نشط لهذا العقار على المنصة. لا يمكن إنشاء تمثيل موازٍ للعقار نفسه.');
                }
                DB::table('property_representation_claims')->where('id', $existing->id)->update([
                    'property_id' => $listing->id,
                    'purpose' => $listing->purpose,
                    'updated_at' => now(),
                ]);
                return;
            }

            // lockForUpdate cannot lock a row that does not exist. Two approvals can
            // therefore both observe no active claim. Let the database's partial
            // unique index arbitrate atomically, then turn the loser into a stable
            // domain conflict instead of leaking a unique-violation SQL error.
            $inserted = DB::table('property_representation_claims')->insertOrIgnore([
                'property_asset_id' => $listing->property_asset_id,
                'property_id' => $listing->id,
                'advertiser_user_id' => $listing->user_id,
                'purpose' => $listing->purpose,
                'status' => 'active',
                'started_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            if ($inserted === 1) return;

            $raceWinner = DB::table('property_representation_claims')
                ->where('property_asset_id', $listing->property_asset_id)
                ->where('status', 'active')
                ->lockForUpdate()
                ->first();
            if (! $raceWinner) {
                throw new ConflictHttpException('تعذر حجز تمثيل العقار بسبب تعارض متزامن. أعد المحاولة.');
            }
            if ((int) $raceWinner->advertiser_user_id !== (int) $listing->user_id) {
                throw new ConflictHttpException('يوجد ممثل نشط لهذا العقار على المنصة. لا يمكن إنشاء تمثيل موازٍ للعقار نفسه.');
            }

            DB::table('property_representation_claims')->where('id', $raceWinner->id)->update([
                'property_id' => $listing->id,
                'purpose' => $listing->purpose,
                'updated_at' => now(),
            ]);
        });
    }

    public function transferRepresentation""",
)

test = "backend-api-runtime/tests/Feature/PropertyIdentityV2Test.php"
replace_once(
    test,
    "use App\\Models\\Role;\nuse App\\Models\\User;\n",
    "use App\\Models\\Property;\nuse App\\Models\\Role;\nuse App\\Models\\User;\nuse App\\Services\\PropertyIdentityService;\n",
)
replace_once(
    test,
    "use Illuminate\\Support\\Facades\\Storage;\nuse Tests\\TestCase;\n",
    "use Illuminate\\Support\\Facades\\Storage;\nuse Symfony\\Component\\HttpKernel\\Exception\\ConflictHttpException;\nuse Tests\\TestCase;\n",
)
replace_once(
    test,
    """    public function test_identity_audit_journal_rejects_mutation(): void
""",
    """    public function test_representation_claim_conflict_is_controlled_and_preserves_the_winner(): void
    {
        [$firstUser, $firstHeaders] = $this->user('identity-claim-1@example.test', '+967733000014');
        [$secondUser, $secondHeaders] = $this->user('identity-claim-2@example.test', '+967733000015');

        $firstId = $this->createReady($firstHeaders, [
            'title' => 'العقار صاحب التمثيل',
            'address' => 'صنعاء حدة شارع 50 منزل 1',
            'latitude' => 15.371000,
            'longitude' => 44.192000,
        ]);
        $secondId = $this->createReady($secondHeaders, [
            'title' => 'عقار ثان لاختبار تعارض التمثيل',
            'address' => 'صنعاء شملان شارع 20 منزل 8',
            'latitude' => 15.430000,
            'longitude' => 44.150000,
        ]);

        $first = Property::query()->findOrFail($firstId);
        $second = Property::query()->findOrFail($secondId);
        $second->forceFill(['property_asset_id' => $first->property_asset_id])->saveQuietly();

        $identity = app(PropertyIdentityService::class);
        $identity->ensureRepresentation($first);
        $identity->ensureRepresentation($first); // idempotent for the same advertiser.

        try {
            $identity->ensureRepresentation($second);
            $this->fail('A competing advertiser must not acquire an active representation claim.');
        } catch (ConflictHttpException $exception) {
            $this->assertSame(409, $exception->getStatusCode());
        }

        $this->assertDatabaseCount('property_representation_claims', 1);
        $this->assertDatabaseHas('property_representation_claims', [
            'property_asset_id' => $first->property_asset_id,
            'property_id' => $first->id,
            'advertiser_user_id' => $firstUser->id,
            'status' => 'active',
        ]);
        $this->assertDatabaseMissing('property_representation_claims', [
            'advertiser_user_id' => $secondUser->id,
            'status' => 'active',
        ]);
    }

    public function test_identity_audit_journal_rejects_mutation(): void
""",
)
