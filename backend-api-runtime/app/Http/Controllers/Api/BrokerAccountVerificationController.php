<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BrokerVerificationDocument;
use App\Models\Role;
use App\Models\User;
use App\Services\AuditLogService;
use App\Services\CloudAssetStorageService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

class BrokerAccountVerificationController extends Controller
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly CloudAssetStorageService $storage,
    ) {}

    public function status(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertBrokerAccount($user);
        return response()->json(['data' => $this->applicationData($user->fresh('brokerVerificationDocuments'))]);
    }

    public function submit(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $this->assertBrokerAccount($user);
        if ($user->broker_verification_status === User::BROKER_VERIFICATION_APPROVED) {
            throw new ConflictHttpException('Broker account is already verified.');
        }

        $request->validate([
            'id_front' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'id_back' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'selfie' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
        ]);

        $stored = [];
        $oldPaths = $user->brokerVerificationDocuments()->pluck('path')->all();
        try {
            DB::transaction(function () use ($request, $user, &$stored): void {
                $user->brokerVerificationDocuments()->delete();
                foreach ([
                    BrokerVerificationDocument::KIND_ID_FRONT => 'id_front',
                    BrokerVerificationDocument::KIND_ID_BACK => 'id_back',
                    BrokerVerificationDocument::KIND_SELFIE => 'selfie',
                ] as $kind => $field) {
                    $file = $request->file($field);
                    $path = $this->storage->storePrivate($file, 'broker_kyc/'.$user->id);
                    if (! is_string($path) || $path === '') {
                        throw new \RuntimeException('Broker verification document could not be stored.');
                    }
                    $stored[] = $path;
                    $user->brokerVerificationDocuments()->create([
                        'kind' => $kind,
                        'path' => $path,
                        'original_name' => $file->getClientOriginalName(),
                        'mime_type' => $file->getMimeType(),
                        'size_bytes' => $file->getSize(),
                    ]);
                }
                $user->forceFill([
                    'broker_verification_status' => User::BROKER_VERIFICATION_PENDING,
                    'broker_verification_submitted_at' => now(),
                    'broker_verified_at' => null,
                    'broker_verified_by_user_id' => null,
                    'broker_verification_note' => null,
                ])->save();
                $this->audit->record($user, 'broker.account_verification_submitted', $user, [
                    'document_kinds' => ['id_front', 'id_back', 'selfie'],
                ], $request, $user->id);
            });
        } catch (\Throwable $e) {
            foreach ($stored as $path) $this->storage->deletePrivate($path);
            throw $e;
        }
        foreach ($oldPaths as $path) $this->storage->deletePrivate($path);

        return response()->json([
            'message' => 'Broker verification was submitted to support.',
            'data' => $this->applicationData($user->fresh('brokerVerificationDocuments')),
        ]);
    }

    public function document(Request $request, User $user, string $kind)
    {
        /** @var User $actor */
        $actor = $request->user();
        if ((int) $actor->id !== (int) $user->id && ! $actor->hasPermission('brokers.verify_accounts')) {
            abort(403);
        }
        if (! in_array($kind, ['id_front', 'id_back', 'selfie'], true)) abort(404);
        $document = $user->brokerVerificationDocuments()->where('kind', $kind)->firstOrFail();
        abort_unless($this->storage->existsPrivate($document->path), 404);
        $this->audit->record($actor, 'broker.account_verification_document_viewed', $document, [
            'broker_user_id' => $user->id,
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
                User::BROKER_VERIFICATION_NOT_SUBMITTED,
                User::BROKER_VERIFICATION_PENDING,
                User::BROKER_VERIFICATION_APPROVED,
                User::BROKER_VERIFICATION_REJECTED,
            ])],
        ]);
        $status = $v['status'] ?? User::BROKER_VERIFICATION_PENDING;
        $rows = User::query()
            ->with('brokerVerificationDocuments')
            ->where('account_type', User::ACCOUNT_TYPE_BROKER)
            ->where('broker_verification_status', $status)
            ->orderByDesc('broker_verification_submitted_at')
            ->orderByDesc('id')
            ->limit(100)
            ->get()
            ->map(fn (User $user) => $this->applicationData($user))
            ->values();
        return response()->json(['data' => $rows]);
    }

    public function approve(Request $request, User $user): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $this->assertBrokerAccount($user);
        if ($user->phone_verified_at === null) {
            throw ValidationException::withMessages(['phone' => ['Broker phone must be verified first.']]);
        }
        if ($user->brokerVerificationDocuments()->whereIn('kind', ['id_front', 'id_back', 'selfie'])->distinct()->count('kind') !== 3) {
            throw new ConflictHttpException('All three broker verification images are required.');
        }
        $v = $request->validate(['note' => ['nullable', 'string', 'max:2000']]);
        DB::transaction(function () use ($actor, $user, $request, $v): void {
            $user->forceFill([
                'broker_verification_status' => User::BROKER_VERIFICATION_APPROVED,
                'broker_verified_at' => now(),
                'broker_verified_by_user_id' => $actor->id,
                'broker_verification_note' => $v['note'] ?? null,
            ])->save();
            $role = Role::query()->where('key', 'broker')->first();
            if ($role) {
                $user->roles()->syncWithoutDetaching([
                    $role->id => ['assigned_by_user_id' => $actor->id, 'created_at' => now()],
                ]);
            }
            $this->audit->record($actor, 'broker.account_verification_approved', $user, [
                'note' => $v['note'] ?? null,
            ], $request, $user->id);
        });
        return response()->json(['message' => 'Broker account verified.', 'data' => $this->applicationData($user->fresh('brokerVerificationDocuments'))]);
    }

    public function reject(Request $request, User $user): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();
        $this->assertBrokerAccount($user);
        $v = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:2000']]);
        DB::transaction(function () use ($actor, $user, $request, $v): void {
            $user->forceFill([
                'broker_verification_status' => User::BROKER_VERIFICATION_REJECTED,
                'broker_verified_at' => null,
                'broker_verified_by_user_id' => $actor->id,
                'broker_verification_note' => $v['reason'],
            ])->save();
            $brokerRole = Role::query()->where('key', 'broker')->first();
            if ($brokerRole) $user->roles()->detach($brokerRole->id);
            $this->audit->record($actor, 'broker.account_verification_rejected', $user, [
                'reason' => $v['reason'],
            ], $request, $user->id);
        });
        return response()->json(['message' => 'Broker verification rejected.', 'data' => $this->applicationData($user->fresh('brokerVerificationDocuments'))]);
    }

    private function assertBrokerAccount(User $user): void
    {
        if (! $user->isBrokerAccount()) {
            throw ValidationException::withMessages(['account_type' => ['This operation is only available to broker accounts.']]);
        }
    }

    private function applicationData(User $user): array
    {
        $user->loadMissing('brokerVerificationDocuments');
        return [
            'user_id' => (int) $user->id,
            'name' => $user->name,
            'phone' => $user->phone,
            'account_type' => $user->account_type,
            'status' => $user->broker_verification_status,
            'submitted_at' => $user->broker_verification_submitted_at?->toIso8601String(),
            'verified_at' => $user->broker_verified_at?->toIso8601String(),
            'note' => $user->broker_verification_note,
            'documents' => $user->brokerVerificationDocuments->map(fn (BrokerVerificationDocument $document) => [
                'kind' => $document->kind,
                'original_name' => $document->original_name,
                'mime_type' => $document->mime_type,
                'size_bytes' => $document->size_bytes,
                'url' => '/api/broker/account-verification/users/'.$user->id.'/documents/'.$document->kind,
            ])->values()->all(),
        ];
    }
}
