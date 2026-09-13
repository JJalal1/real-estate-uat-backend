from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one match in {path}, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "backend-api-runtime/app/Services/PropertyIdentityService.php",
    """        $type = (string) ($listing['type'] ?? '');
        $errors = [];
        if (in_array($type, self::UNIT_TYPES, true)) {
""",
    """        $type = (string) ($listing['type'] ?? '');
        $inputVersion = (int) ($listing['listing_input_version'] ?? 1);
        $errors = [];
        if ($inputVersion >= 3 && in_array($type, self::UNIT_TYPES, true)) {
""",
)

replace_once(
    "backend-api-runtime/app/Services/PropertyIdentityService.php",
    """        $type = (string) $listing['type'];
        $kind = $this->kindForType($type);
        $address = $this->normalizedText((string) ($listing['address'] ?? ''));
""",
    """        $type = (string) $listing['type'];
        $kind = $this->kindForType($type);
        $inputVersion = (int) ($listing['listing_input_version'] ?? 1);
        if (
            $kind === 'unit'
            && $inputVersion < 3
            && (
                trim((string) ($listing['building_reference'] ?? '')) === ''
                || trim((string) ($listing['unit_number'] ?? '')) === ''
            )
        ) {
            // Legacy v1/v2 clients did not send unit identity fields. Preserve
            // their contract while v3+ uses the stricter unit identity model.
            $kind = 'standalone';
        }
        $address = $this->normalizedText((string) ($listing['address'] ?? ''));
""",
)

replace_once(
    "backend-api-runtime/app/Http/Controllers/Api/PropertyController.php",
    """        $asset=$this->identity->resolveOrCreateAsset($user,$validated);
        $storedPublic=[];$storedPrivate=[];
""",
    """        $asset=$this->identity->resolveOrCreateAsset($user,$validated);
        $this->assets->assertPurposeNotBlocked($asset,(string)$validated['purpose']);
        $storedPublic=[];$storedPrivate=[];
""",
)

replace_once(
    "backend-api-runtime/tests/Feature/PropertyIdentityV2Test.php",
    """            'latitude' => 15.300000, 'longitude' => 44.210000, 'area_m2' => 180, 'bedrooms' => 3, 'bathrooms' => 2,
""",
    """            'latitude' => 15.300000, 'longitude' => 44.210000, 'area_m2' => 180, 'area_value' => 180, 'bedrooms' => 3, 'bathrooms' => 2,
""",
)
replace_once(
    "backend-api-runtime/tests/Feature/PropertyIdentityV2Test.php",
    """            'latitude' => 15.300090, 'longitude' => 44.210040, 'area_m2' => 340, 'bedrooms' => 5, 'bathrooms' => 4,
""",
    """            'latitude' => 15.300300, 'longitude' => 44.210040, 'area_m2' => 340, 'area_value' => 340, 'bedrooms' => 5, 'bathrooms' => 4,
""",
)

replace_once(
    "backend-api-runtime/tests/Feature/Phase2ListingJourneyApiTest.php",
    """            'address' => 'صنعاء - حدة - شارع المدرسة',
            'latitude' => 15.369520,
            'longitude' => 44.191080,
""",
    """            'address' => 'صنعاء حدة جوار السوق الخلفي',
            'latitude' => 15.369700,
            'longitude' => 44.191120,
""",
)

replace_once(
    "backend-api-runtime/tests/Feature/Phase2ListingJourneyApiTest.php",
    """        $this->withHeaders($firstHeaders)
            ->postJson(\"/api/properties/$firstId/submit\")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($secondHeaders)
            ->postJson(\"/api/properties/$secondId/submit\")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
""",
    """        $this->withHeaders($firstHeaders)
            ->postJson(\"/api/properties/$firstId/submit\")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
        $this->withHeaders($secondHeaders)
            ->postJson(\"/api/properties/$secondId/identity/self-verify\", [
                'assert_different' => true,
                'difference_type' => 'different_address',
                'difference_note' => 'العقاران متجاوران لكن لكل منهما عنوان ومدخل مستقل عن الآخر.',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'needs_support');
        $this->withHeaders($secondHeaders)
            ->postJson(\"/api/properties/$secondId/submit\")
            ->assertOk()
            ->assertJsonPath('data.review_status', 'submitted');
""",
)
