<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AccountVerificationDocument;
use App\Models\AccountVerificationProfile;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use App\Services\UserNotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class AccountVerificationController extends Controller
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly CloudAssetStorageService $storage,
        private readonly UserNotificationService $notifications,
    ) {}

    public function status(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        return response()->json(['data' => $this->applicationData($user)]);
    }

    public function submit(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        if ($user->profile_completed_at === null) {
            throw new ConflictHttpException('أكمل الاسم الرباعي أولاً قبل إرسال طلب التحقق.');
        }

        $base = $request->validate([
            'type' => ['required', Rule::in([
                AccountVerificationProfile::TYPE_OWNER,
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ])],
            'governorate' => ['required', 'string', 'min:2', 'max:120'],
            'district' => ['required', 'string', 'min:2', 'max:120'],
            'identity_document' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'identity_back' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'selfie' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'professional_license' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'commercial_register' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'office_license' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'office_frontage' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'office_logo' => ['nullable', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'work_areas_json' => ['nullable', 'string', 'max:5000'],
            'specialties_json' => ['nullable', 'string', 'max:5000'],
            'office_name' => ['nullable', 'string', 'max:160'],
            'commercial_register_number' => ['nullable', 'string', 'max:120'],
            'neighborhood' => ['nullable', 'string', 'max:120'],
            'street' => ['nullable', 'string', 'max:160'],
            'landmark' => ['nullable', 'string', 'max:160'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'office_phone' => ['nullable', 'string', 'max:32', 'regex:/^\+?[0-9]{7,20}$/'],
        ]);

        $type = (string) $base['type'];
        $details = [
            'governorate' => trim((string) $base['governorate']),
            'district' => trim((string) $base['district']),
        ];

        if ($type === AccountVerificationProfile::TYPE_BROKER) {
            $workAreas = $this->jsonStringList($request->input('work_areas_json'), 'work_areas_json', true, 20);
            $specialties = $this->jsonStringList($request->input('specialties_json'), 'specialties_json', false, 20);
            $details['work_areas'] = $workAreas;
            $details['specialties'] = $specialties;
        }

        if ($type === AccountVerificationProfile::TYPE_OFFICE) {
            $office = $request->validate([
                'office_name' => ['required', 'string', 'min:2', 'max:160'],
                'commercial_register_number' => ['required', 'string', 'min:2', 'max:120'],
                'neighborhood' => ['required', 'string', 'min:2', 'max:120'],
                'street' => ['required', 'string', 'min:2', 'max:160'],
                'landmark' => ['required', 'string', 'min:2', 'max:160'],
                'latitude' => ['required', 'numeric', 'between:-90,90'],
                'longitude' => ['required', 'numeric', 'between:-180,180'],
                'office_phone' => ['required', 'string', 'max:32', 'regex:/^\+?[0-9]{7,20}$/'],
            ]);
            $details = array_merge($details, [
                'office_name' => trim((string) $office['office_name']),
                'commercial_register_number' => trim((string) $office['commercial_register_number']),
                'neighborhood' => trim((string) $office['neighborhood']),
                'street' => trim((string) $office['street']),
                'landmark' => trim((string) $office['landmark']),
                'latitude' => (float) $office['latitude'],
                'longitude' => (float) $office['longitude'],
                'office_phone' => trim((string) $office['office_phone']),
            ]);
        }

        $profile = $user->accountVerificationProfile()->with('documents')->first();
        $switchingType = $profile !== null && $profile->type !== $type;
        $existingKinds = $switchingType
            ? collect()
            : ($profile?->documents?->pluck('kind') ?? collect());

        $requiredKinds = $this->requiredDocumentKinds($type);
        $missingKinds = collect($requiredKinds)->filter(
            fn (string $kind) => ! $request->hasFile($kind) && ! $existingKinds->contains($kind)
        )->values();
        if ($missingKinds->isNotEmpty()) {
            throw ValidationException::withMessages([
                'documents' => ['أكمل المستندات المطلوبة قبل إرسال طلب التحقق: '.implode(', ', $missingKinds->all())],
            ]);
        }

        $allowedKinds = $this->allowedDocumentKinds($type);
        $stored = [];
        $uploaded = [];
        try {
            foreach ($allowedKinds as $kind) {
                if (! $request->hasFile($kind)) continue;
                $file = $request->file($kind);
                if (! $file) continue;
                $path = $this->storage->storePrivate($file, 'account_verification/'.$user->id);
                if (! is_string($path) || $path === '') {
                    throw new \RuntimeException('Account verification document could not be stored.');
                }
                $stored[] = $path;
                $uploaded[$kind] = [
                    'path' => $path,
                    'original_name' => $file->getClientOriginalName(),
                    'mime_type' => $file->getMimeType(),
                    'size_bytes' => $file->getSize(),
                ];
            }

            $oldPaths = [];
            DB::transaction(function () use ($user, $type, $details, $profile, $switchingType, $uploaded, $request, &$oldPaths): void {
                if ($profile === null) {
                    $profile = $user->accountVerificationProfile()->create([
                        'type' => $type,
                        'status' => AccountVerificationProfile::STATUS_NOT_SUBMITTED,
                        'details' => $details,
                    ]);
                } elseif ($switchingType) {
                    $oldPaths = $profile->documents()->pluck('path')->all();
                    $profile->documents()->delete();
                }

                foreach ($uploaded as $kind => $fileData) {
                    $old = $profile->documents()->where('kind', $kind)->first();
                    if ($old) {
                        $oldPaths[] = $old->path;
                        $old->delete();
                    }
                    $profile->documents()->create(array_merge(['kind' => $kind], $fileData));
                }

                $profile->forceFill([
                    'type' => $type,
                    'status' => AccountVerificationProfile::STATUS_PENDING,
                    'details' => $details,
                    'submitted_at' => now(),
                    'reviewed_at' => null,
                    'reviewed_by_user_id' => null,
                    'review_note' => null,
                ])->save();

                $this->audit->record($user, 'account.verification_submitted', $profile, [
                    'type' => $type,
                    'document_kinds' => $profile->documents()->pluck('kind')->sort()->values()->all(),
                ], $request, $user->id);
            });

            foreach (array_unique($oldPaths) as $path) {
                if (! in_array($path, $stored, true)) $this->storage->deletePrivate($path);
            }
        } catch (\Throwable $e) {
            foreach ($stored as $path) $this->storage->deletePrivate($path);
            throw $e;
        }

        return response()->json([
            'message' => 'تم استلام طلب التحقق بنجاح.',
            'data' => $this->applicationData($user->fresh()),
        ]);
    }

    public function document(Request $request, User $user, string $kind)
    {
        /** @var User $actor */
        $actor = $request->user();
        if ((int) $actor->id !== (int) $user->id && ! $actor->hasPermission('accounts.verify_profiles')) {
            abort(403);
        }
        $profile = $user->accountVerificationProfile()->firstOrFail();
        $document = $profile->documents()->where('kind', $kind)->firstOrFail();
        abort_unless($this->storage->existsPrivate($document->path), 404);
        $this->audit->record($actor, 'account.verification_document_viewed', $document, [
            'target_user_id' => $user->id,
            'kind' => $kind,
        ], $request, $user->id);
        return $this->storage->responsePrivate($document->path, $document->original_name, [
            'Cache-Control' => 'private, no-store',
        ]);
    }

    public function adminIndex(Request $request): JsonResponse
    {
        $v = $request->validate([
            'status' => ['nullable', Rule::in([
                AccountVerificationProfile::STATUS_NOT_SUBMITTED,
                AccountVerificationProfile::STATUS_PENDING,
                AccountVerificationProfile::STATUS_APPROVED,
                AccountVerificationProfile::STATUS_REJECTED,
                AccountVerificationProfile::STATUS_NEEDS_MORE_INFO,
            ])],
            'type' => ['nullable', Rule::in([
                AccountVerificationProfile::TYPE_OWNER,
                AccountVerificationProfile::TYPE_BROKER,
                AccountVerificationProfile::TYPE_OFFICE,
            ])],
        ]);
        $status = $v['status'] ?? AccountVerificationProfile::STATUS_PENDING;
        $q = AccountVerificationProfile::query()
            ->with(['user', 'documents'])
            ->where('status', $status);
        if (! empty($v['type'])) $q->where('type', $v['type']);
        $rows = $q->orderByDesc('submitted_at')->orderByDesc('id')->limit(100)->get()
            ->map(fn (AccountVerificationProfile $profile) => $this->profileData($profile->user, $profile))
            ->values();
        return response()->json(['data' => $rows]);
    }

    public function approve(Request $request, User $user): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $profile = $user->accountVerificationProfile()->with('documents')->firstOrFail();
        $this->assertReadyForReview($profile);
        $v = $request->validate(['note' => ['nullable', 'string', 'max:2000']]);

        DB::transaction(function () use ($actor, $user, $profile, $request, $v): void {
            $profile->forceFill([
                'status' => AccountVerificationProfile::STATUS_APPROVED,
                'reviewed_at' => now(),
                'reviewed_by_user_id' => $actor->id,
                'review_note' => $v['note'] ?? null,
            ])->save();
            $this->audit->record($actor, 'account.verification_approved', $profile, [
                'type' => $profile->type,
                'note' => $v['note'] ?? null,
            ], $request, $user->id);
        });

        $this->notifications->create(
            $user->id,
            'account_verification_approved',
            'تم اعتماد نوع الحساب',
            'اكتملت مراجعة طلب التحقق وتم اعتماد حسابك.',
            'account_verification_profile',
            $profile->id,
            ['type' => $profile->type, 'status' => AccountVerificationProfile::STATUS_APPROVED],
        );

        return response()->json([
            'message' => 'Account verification approved.',
            'data' => $this->applicationData($user->fresh()),
        ]);
    }

    public function requestMoreInfo(Request $request, User $user): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $profile = $user->accountVerificationProfile()->firstOrFail();
        $this->assertReviewStatusOpen($profile);
        $v = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:2000']]);
        $profile->forceFill([
            'status' => AccountVerificationProfile::STATUS_NEEDS_MORE_INFO,
            'reviewed_at' => now(),
            'reviewed_by_user_id' => $actor->id,
            'review_note' => $v['reason'],
        ])->save();
        $this->audit->record($actor, 'account.verification_more_info_requested', $profile, [
            'reason' => $v['reason'],
        ], $request, $user->id);
        $this->notifications->create(
            $user->id,
            'account_verification_more_info',
            'طلب التحقق يحتاج مستندًا أو توضيحًا إضافيًا',
            $v['reason'],
            'account_verification_profile',
            $profile->id,
            ['type' => $profile->type, 'status' => AccountVerificationProfile::STATUS_NEEDS_MORE_INFO],
        );
        return response()->json(['message' => 'More information requested.', 'data' => $this->applicationData($user->fresh())]);
    }

    public function reject(Request $request, User $user): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $profile = $user->accountVerificationProfile()->firstOrFail();
        $this->assertReviewStatusOpen($profile);
        $v = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:2000']]);
        $profile->forceFill([
            'status' => AccountVerificationProfile::STATUS_REJECTED,
            'reviewed_at' => now(),
            'reviewed_by_user_id' => $actor->id,
            'review_note' => $v['reason'],
        ])->save();
        $this->audit->record($actor, 'account.verification_rejected', $profile, [
            'reason' => $v['reason'],
        ], $request, $user->id);
        $this->notifications->create(
            $user->id,
            'account_verification_rejected',
            'تم تحديث طلب التحقق',
            $v['reason'],
            'account_verification_profile',
            $profile->id,
            ['type' => $profile->type, 'status' => AccountVerificationProfile::STATUS_REJECTED],
        );
        return response()->json(['message' => 'Account verification rejected.', 'data' => $this->applicationData($user->fresh())]);
    }

    private function applicationData(User $user): array
    {
        $profile = $user->accountVerificationProfile()->with('documents')->first();
        if (! $profile) {
            return [
                'user_id' => (int) $user->id,
                'name' => $user->name,
                'phone' => $user->phone,
                'type' => null,
                'status' => AccountVerificationProfile::STATUS_NOT_SUBMITTED,
                'details' => new \stdClass(),
                'documents' => [],
                'verification_flags' => $this->verificationFlags(null),
            ];
        }
        return $this->profileData($user, $profile);
    }

    private function profileData(User $user, AccountVerificationProfile $profile): array
    {
        $profile->loadMissing('documents');
        return [
            'user_id' => (int) $user->id,
            'name' => $user->name,
            'phone' => $user->phone,
            'type' => $profile->type,
            'status' => $profile->status,
            'details' => $profile->details ?? new \stdClass(),
            'submitted_at' => $profile->submitted_at?->toIso8601String(),
            'reviewed_at' => $profile->reviewed_at?->toIso8601String(),
            'note' => $profile->review_note,
            'documents' => $profile->documents->map(fn (AccountVerificationDocument $document) => [
                'kind' => $document->kind,
                'original_name' => $document->original_name,
                'mime_type' => $document->mime_type,
                'size_bytes' => $document->size_bytes,
                'url' => '/api/account-verification/users/'.$user->id.'/documents/'.$document->kind,
            ])->values(),
            'verification_flags' => $this->verificationFlags($profile),
        ];
    }

    private function verificationFlags(?AccountVerificationProfile $profile): array
    {
        $approved = $profile?->isApproved() === true;
        $kinds = $profile?->documents?->pluck('kind') ?? collect();
        return [
            'identity_reviewed' => $approved,
            'professional_document_reviewed' => $approved
                && $profile?->type === AccountVerificationProfile::TYPE_BROKER
                && $kinds->contains(AccountVerificationDocument::PROFESSIONAL_LICENSE),
            'commercial_register_reviewed' => $approved
                && $profile?->type === AccountVerificationProfile::TYPE_OFFICE
                && $kinds->contains(AccountVerificationDocument::COMMERCIAL_REGISTER),
            'office_documents_reviewed' => $approved
                && $profile?->type === AccountVerificationProfile::TYPE_OFFICE
                && $kinds->contains(AccountVerificationDocument::OFFICE_LICENSE),
            'office_location_registered' => $approved
                && $profile?->type === AccountVerificationProfile::TYPE_OFFICE
                && isset(($profile->details ?? [])['latitude'], ($profile->details ?? [])['longitude']),
        ];
    }

    private function requiredDocumentKinds(string $type): array
    {
        return match ($type) {
            AccountVerificationProfile::TYPE_OWNER => [
                AccountVerificationDocument::IDENTITY_DOCUMENT,
                AccountVerificationDocument::SELFIE,
            ],
            AccountVerificationProfile::TYPE_BROKER => [
                AccountVerificationDocument::IDENTITY_DOCUMENT,
                AccountVerificationDocument::SELFIE,
            ],
            AccountVerificationProfile::TYPE_OFFICE => [
                AccountVerificationDocument::RESPONSIBLE_IDENTITY,
                AccountVerificationDocument::SELFIE,
                AccountVerificationDocument::COMMERCIAL_REGISTER,
                AccountVerificationDocument::OFFICE_LICENSE,
                AccountVerificationDocument::OFFICE_FRONTAGE,
            ],
            default => [],
        };
    }

    private function allowedDocumentKinds(string $type): array
    {
        return match ($type) {
            AccountVerificationProfile::TYPE_OWNER => [
                AccountVerificationDocument::IDENTITY_DOCUMENT,
                AccountVerificationDocument::IDENTITY_BACK,
                AccountVerificationDocument::SELFIE,
            ],
            AccountVerificationProfile::TYPE_BROKER => [
                AccountVerificationDocument::IDENTITY_DOCUMENT,
                AccountVerificationDocument::IDENTITY_BACK,
                AccountVerificationDocument::SELFIE,
                AccountVerificationDocument::PROFESSIONAL_LICENSE,
            ],
            AccountVerificationProfile::TYPE_OFFICE => [
                AccountVerificationDocument::RESPONSIBLE_IDENTITY,
                AccountVerificationDocument::IDENTITY_BACK,
                AccountVerificationDocument::SELFIE,
                AccountVerificationDocument::COMMERCIAL_REGISTER,
                AccountVerificationDocument::OFFICE_LICENSE,
                AccountVerificationDocument::OFFICE_FRONTAGE,
                AccountVerificationDocument::OFFICE_LOGO,
            ],
            default => [],
        };
    }

    private function assertReadyForReview(AccountVerificationProfile $profile): void
    {
        $this->assertReviewStatusOpen($profile);

        $present = $profile->documents->pluck('kind');
        $missing = collect($this->requiredDocumentKinds($profile->type))->diff($present);
        if ($missing->isNotEmpty()) {
            throw new ConflictHttpException('Required account verification documents are missing.');
        }

        $details = $profile->details ?? [];
        foreach (['governorate', 'district'] as $key) {
            if (trim((string) ($details[$key] ?? '')) === '') {
                throw new ConflictHttpException('Account verification residence details are incomplete.');
            }
        }

        if ($profile->type === AccountVerificationProfile::TYPE_BROKER) {
            $areas = $details['work_areas'] ?? [];
            if (! is_array($areas) || collect($areas)->filter(fn ($value) => trim((string) $value) !== '')->isEmpty()) {
                throw new ConflictHttpException('Broker work areas are required before approval.');
            }
        }

        if ($profile->type === AccountVerificationProfile::TYPE_OFFICE) {
            foreach (['office_name', 'commercial_register_number', 'neighborhood', 'street', 'landmark', 'office_phone'] as $key) {
                if (trim((string) ($details[$key] ?? '')) === '') {
                    throw new ConflictHttpException('Office verification details are incomplete.');
                }
            }
            if (! isset($details['latitude'], $details['longitude'])) {
                throw new ConflictHttpException('Office map location is required before approval.');
            }
        }
    }

    private function assertReviewStatusOpen(AccountVerificationProfile $profile): void
    {
        if (! in_array($profile->status, [
            AccountVerificationProfile::STATUS_PENDING,
            AccountVerificationProfile::STATUS_NEEDS_MORE_INFO,
        ], true)) {
            throw new ConflictHttpException('Account verification is not awaiting review.');
        }
    }

    private function jsonStringList(mixed $value, string $field, bool $required, int $max): array
    {
        if ($value === null || trim((string) $value) === '') {
            if ($required) {
                throw ValidationException::withMessages([$field => ['أدخل منطقة عمل واحدة على الأقل.']]);
            }
            return [];
        }
        $decoded = json_decode((string) $value, true);
        if (! is_array($decoded)) {
            throw ValidationException::withMessages([$field => ['القيمة المرسلة غير صالحة.']]);
        }
        $items = collect($decoded)
            ->map(fn ($item) => trim((string) $item))
            ->filter(fn (string $item) => $item !== '')
            ->unique()
            ->values();
        if ($required && $items->isEmpty()) {
            throw ValidationException::withMessages([$field => ['أدخل منطقة عمل واحدة على الأقل.']]);
        }
        if ($items->count() > $max || $items->contains(fn (string $item) => mb_strlen($item) > 120)) {
            throw ValidationException::withMessages([$field => ['القائمة طويلة أو تحتوي قيمة غير صالحة.']]);
        }
        return $items->all();
    }
}
