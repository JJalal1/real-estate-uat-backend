from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def patch(path, old, new, count=1):
    p = ROOT / path
    text = p.read_text()
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f"pattern missing in {path}: expected >= {count}, got {actual}: {old[:120]!r}")
    text = text.replace(old, new, count)
    p.write_text(text)

# Routes
path = 'backend-api-runtime/routes/api.php'
patch(path,
      "use App\\Http\\Controllers\\Api\\PropertyFavoriteController;\n",
      "use App\\Http\\Controllers\\Api\\PropertyFavoriteController;\nuse App\\Http\\Controllers\\Api\\PropertyIdentityController;\n")
patch(path,
      "    Route::post('/properties/{property}/submit', [PropertyController::class, 'submit']);\n",
      "    Route::post('/properties/{property}/submit', [PropertyController::class, 'submit']);\n"
      "    Route::post('/properties/{property}/identity/check', [PropertyIdentityController::class, 'check']);\n"
      "    Route::post('/properties/{property}/identity/self-verify', [PropertyIdentityController::class, 'selfVerify']);\n")
patch(path,
      "        Route::post('/listings/{property}/link-property', [ListingReviewController::class, 'linkPropertyAsset'])->middleware('permission:listings.moderate');\n",
      "        Route::post('/listings/{property}/link-property', [ListingReviewController::class, 'linkPropertyAsset'])->middleware('permission:listings.moderate');\n"
      "        Route::post('/listings/{property}/transfer-representation', [PropertyIdentityController::class, 'transferRepresentation'])->middleware('permission:listings.manage_blocks');\n")

# PropertyController integration
path = 'backend-api-runtime/app/Http/Controllers/Api/PropertyController.php'
patch(path,
      "use App\\Services\\PropertyAssetService;\n",
      "use App\\Services\\PropertyAssetService;\nuse App\\Services\\PropertyIdentityService;\n")
patch(path,
      "        private readonly PropertyAssetService $assets,\n        private readonly ListingWorkflowService $workflow,\n",
      "        private readonly PropertyAssetService $assets,\n        private readonly PropertyIdentityService $identity,\n        private readonly ListingWorkflowService $workflow,\n")
patch(path,
      "$asset=$this->assets->resolveOrCreate($user,$validated,null);",
      "$asset=$this->identity->resolveOrCreateAsset($user,$validated);")
patch(path,
      "$asset=$this->assets->resolveOrCreate($user,$identity,null);$property->property_asset_id=$asset->id;",
      "$asset=$this->identity->resolveOrCreateAsset($user,$identity);$property->property_asset_id=$asset->id;")
patch(path,
      "        DB::transaction(function()use($property,$user,$request):void{$property->delete();$this->audit->record($user,'listing.deleted',$property,['property_asset_id'=>$property->property_asset_id],$request,$user->id);});\n",
      "        DB::transaction(function()use($property,$user,$request):void{$this->identity->releaseRepresentationForListing($property);$property->delete();$this->audit->record($user,'listing.deleted',$property,['property_asset_id'=>$property->property_asset_id],$request,$user->id);});\n")
patch(path,
      "            'listing_input_version' => ['nullable', 'integer', Rule::in([1, 2])],\n",
      "            'listing_input_version' => ['nullable', 'integer', Rule::in([1, 2, 3])],\n")
patch(path,
      "            'address' => ['nullable', 'string', 'max:255'],\n",
      "            'address' => ['nullable', 'string', 'max:255'],\n"
      "            'building_reference' => ['nullable', 'string', 'max:160'],\n"
      "            'unit_number' => ['nullable', 'string', 'max:64'],\n"
      "            'floor_number' => ['nullable', 'string', 'max:32'],\n"
      "            'land_boundary_geojson' => ['nullable'],\n")
patch(path,
      "            'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms', 'has_parking', 'building_facade', 'address', 'latitude', 'longitude',\n",
      "            'area_m2', 'area_value', 'area_unit', 'bedrooms', 'bathrooms', 'has_parking', 'building_facade', 'address', 'latitude', 'longitude',\n"
      "            'building_reference', 'unit_number', 'floor_number', 'land_boundary_geojson',\n")
patch(path,
      "        if (($payload['type'] ?? null) === 'land') {\n            $payload['bedrooms'] = null;\n            $payload['bathrooms'] = null;\n        }\n",
      "        if (($payload['type'] ?? null) === 'land') {\n            $payload['bedrooms'] = null;\n            $payload['bathrooms'] = null;\n            $payload['building_reference'] = null;\n            $payload['unit_number'] = null;\n            $payload['floor_number'] = null;\n        } elseif (! in_array(($payload['type'] ?? null), ['apartment','office','shop'], true)) {\n            $payload['building_reference'] = null;\n            $payload['unit_number'] = null;\n            $payload['floor_number'] = null;\n            $payload['land_boundary_geojson'] = null;\n        } else {\n            $payload['land_boundary_geojson'] = null;\n        }\n")
patch(path,
      "            $validated['building_facade'] = null;\n        }\n\n        return $validated;\n",
      "            $validated['building_facade'] = null;\n            $validated['building_reference'] = null;\n            $validated['unit_number'] = null;\n            $validated['floor_number'] = null;\n        } elseif (! in_array($effectiveType, ['apartment','office','shop'], true)) {\n            $validated['building_reference'] = null;\n            $validated['unit_number'] = null;\n            $validated['floor_number'] = null;\n            $validated['land_boundary_geojson'] = null;\n        } else {\n            $validated['land_boundary_geojson'] = null;\n        }\n\n        return $validated;\n")
patch(path,
      "            'owner_relationship_note' => $property->owner_relationship_note,\n        ];\n",
      "            'owner_relationship_note' => $property->owner_relationship_note,\n"
      "            'building_reference' => $property->building_reference,\n"
      "            'unit_number' => $property->unit_number,\n"
      "            'floor_number' => $property->floor_number,\n"
      "            'land_boundary_geojson' => $property->land_boundary_geojson,\n"
      "        ];\n")
patch(path,
      "            'owner_relationship_note' => $property->owner_relationship_note,\n            'ownership_proof_present' => $property->documents->contains(\n",
      "            'owner_relationship_note' => $property->owner_relationship_note,\n"
      "            'building_reference' => $property->building_reference,\n"
      "            'unit_number' => $property->unit_number,\n"
      "            'floor_number' => $property->floor_number,\n"
      "            'land_boundary_geojson' => $property->land_boundary_geojson,\n"
      "            'duplicate_check_status' => $property->duplicate_check_status,\n"
      "            'duplicate_check_score' => (int) $property->duplicate_check_score,\n"
      "            'duplicate_check_metadata' => $property->duplicate_check_metadata,\n"
      "            'ownership_proof_present' => $property->documents->contains(\n")
patch(path,
      "            $data['owner_relationship_note'] = $property->owner_relationship_note;\n            $data['ownership_proof_present'] = $property->documents()->where('kind', 'ownership_proof')->exists();\n",
      "            $data['owner_relationship_note'] = $property->owner_relationship_note;\n"
      "            $data['building_reference'] = $property->building_reference;\n"
      "            $data['unit_number'] = $property->unit_number;\n"
      "            $data['floor_number'] = $property->floor_number;\n"
      "            $data['land_boundary_geojson'] = $property->land_boundary_geojson;\n"
      "            $data['duplicate_check_status'] = $property->duplicate_check_status;\n"
      "            $data['duplicate_check_score'] = (int) $property->duplicate_check_score;\n"
      "            $data['duplicate_check_metadata'] = $property->duplicate_check_metadata;\n"
      "            $data['ownership_proof_present'] = $property->documents()->where('kind', 'ownership_proof')->exists();\n")

# ListingWorkflowService: automated decision before support is involved for duplicate logic.
path = 'backend-api-runtime/app/Services/ListingWorkflowService.php'
patch(path,
      "        private readonly PropertyAssetService $assets,\n        private readonly RegionService $regions,\n",
      "        private readonly PropertyAssetService $assets,\n        private readonly PropertyIdentityService $identity,\n        private readonly RegionService $regions,\n")
patch(path,
      "            $this->assets->assertNotAlreadyPublished($asset, $locked->purpose, $locked->id);\n            $this->regions->assertListingAllowed($actor, (float) $locked->latitude, (float) $locked->longitude);\n\n            $from = $locked->review_status;\n",
      "            $this->assets->assertNotAlreadyPublished($asset, $locked->purpose, $locked->id);\n            $identityResult = $this->identity->assertSubmissionAllowed($actor, $locked);\n            $this->regions->assertListingAllowed($actor, (float) $locked->latitude, (float) $locked->longitude);\n\n            $from = $locked->review_status;\n")
old = """            $candidates = $this->assets->likelyDuplicates($locked);\n            if ($candidates !== []) {\n                $this->review(\n                    $actor,\n                    $locked,\n                    'duplicate_suspected',\n                    'submitted',\n                    'submitted',\n                    'Likely duplicate signals require human review before approval.',\n                    ['candidates' => $candidates],\n                );\n            }\n\n            $this->audit->record(\n                $actor,\n                'listing.submitted',\n                $locked,\n                [\n                    'review_status' => 'submitted',\n                    'likely_duplicate_count' => count($candidates),\n                ],\n                $request,\n                $actor->id,\n            );\n"""
new = """            if (($identityResult['decision'] ?? 'distinct') === 'possible_duplicate') {\n                $this->review(\n                    $actor,\n                    $locked,\n                    'duplicate_suspected_after_self_verification',\n                    'submitted',\n                    'submitted',\n                    'Automated identity checks remained ambiguous after advertiser self-verification.',\n                    ['identity_result' => $identityResult],\n                );\n            }\n\n            $this->audit->record(\n                $actor,\n                'listing.submitted',\n                $locked,\n                [\n                    'review_status' => 'submitted',\n                    'property_identity_status' => $identityResult['status'] ?? 'distinct',\n                    'property_identity_score' => $identityResult['score'] ?? 0,\n                ],\n                $request,\n                $actor->id,\n            );\n"""
patch(path, old, new)
old = """            $candidates = $this->assets->likelyDuplicates($locked);\n            if ($candidates !== []) {\n                $acknowledgement = trim((string) $duplicateReviewReason);\n                if (mb_strlen($acknowledgement) < 10) {\n                    throw ValidationException::withMessages([\n                        'duplicate_review_reason' => [\n                            'توجد عقارات مشابهة محتملة. راجع المرشحات وسجل سبب اعتبار الإعلان غير مكرر، أو اربطه بهوية العقار الصحيحة قبل الموافقة.',\n                        ],\n                    ]);\n                }\n                $this->review(\n                    $actor,\n                    $locked,\n                    'duplicate_review_cleared',\n                    $locked->review_status,\n                    $locked->review_status,\n                    $acknowledgement,\n                    ['candidates' => $candidates],\n                );\n                $this->audit->record(\n                    $actor,\n                    'listing.duplicate_review_cleared',\n                    $locked,\n                    [\n                        'reason' => $acknowledgement,\n                        'candidate_listing_ids' => array_column($candidates, 'listing_id'),\n                    ],\n                    $request,\n                    $locked->user_id,\n                );\n            }\n\n            $from = $locked->review_status;\n"""
new = """            $identityResult = $this->identity->assertApprovalAllowed($actor, $locked, $duplicateReviewReason);\n            if (($identityResult['decision'] ?? 'distinct') === 'possible_duplicate') {\n                $acknowledgement = trim((string) $duplicateReviewReason);\n                $this->review(\n                    $actor,\n                    $locked,\n                    'duplicate_review_cleared',\n                    $locked->review_status,\n                    $locked->review_status,\n                    $acknowledgement,\n                    ['identity_result' => $identityResult],\n                );\n                $this->audit->record(\n                    $actor,\n                    'listing.duplicate_review_cleared',\n                    $locked,\n                    ['reason' => $acknowledgement, 'identity_result' => $identityResult],\n                    $request,\n                    $locked->user_id,\n                );\n            }\n\n            $this->identity->ensureRepresentation($locked);\n            $from = $locked->review_status;\n"""
patch(path, old, new)
patch(path,
      "                ['reason' => $reason, 'duplicate_candidates_reviewed' => count($candidates)],\n",
      "                ['reason' => $reason, 'property_identity_status' => $identityResult['status'] ?? 'distinct'],\n")
patch(path,
      "            'review_status' => $listing->review_status,\n        ];\n",
      "            'review_status' => $listing->review_status,\n"
      "            'duplicate_check_status' => $listing->duplicate_check_status,\n"
      "            'building_reference' => $listing->building_reference,\n"
      "            'unit_number' => $listing->unit_number,\n"
      "            'floor_number' => $listing->floor_number,\n"
      "        ];\n")

print('Property Identity V2 backend integration applied')
