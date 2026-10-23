<?php

namespace App\Services;

use App\Models\ListingEditorDraft;
use App\Models\ListingImageUploadIntent;
use App\Models\Property;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ListingImageUploadIntentService
{
    public function __construct(
        private readonly ListingEditorDraftService $drafts,
        private readonly ListingImageService $images,
        private readonly CloudAssetStorageService $cloud,
    ) {}

    public function issue(User $actor, string $draftKey, string $imageKey, string $sha, int $bytes, string $mime, int $revision): array
    {
        abort_unless(config('listing_media.resumable_uploads_enabled', false), 404);
        abort_unless(Str::isUuid($imageKey) && preg_match('/^[a-f0-9]{64}$/D', $sha), 422);
        abort_unless($bytes > 0 && $bytes <= config('listing_media.max_bytes'), 422);
        abort_unless(in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true), 422);
        $intent = DB::transaction(function () use ($actor, $draftKey, $imageKey, $sha, $bytes, $mime, $revision) {
            User::query()->lockForUpdate()->findOrFail($actor->id);
            $draft = $this->drafts->owned($actor, $draftKey, true);
            $this->drafts->assertEditable($actor, $draft->property_id ? Property::findOrFail($draft->property_id) : null);
            abort_unless(in_array($imageKey, $draft->payload['image_order'] ?? [], true), 409);
            abort_if(isset($draft->images[$imageKey]), 409);
            $this->drafts->assertRevision($draft, $revision);
            abort_if(count($draft->images) >= 12, 422);
            $existing = ListingImageUploadIntent::query()->where('listing_editor_draft_id', $draft->id)
                ->where('image_key', $imageKey)->lockForUpdate()->first();
            if ($existing) {
                abort_unless($existing->sha256 === $sha && $existing->byte_length === $bytes
                    && $existing->mime === $mime && $existing->status === 'pending'
                    && $existing->signed_until->isFuture(), 409);
                return $existing;
            }
            $extension = ['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp'][$mime];
            return ListingImageUploadIntent::create([
                'user_id'=>$actor->id, 'listing_editor_draft_id'=>$draft->id,
                'image_key'=>$imageKey, 'sha256'=>$sha, 'byte_length'=>$bytes,
                'mime'=>$mime,
                'path'=>'editor-drafts/'.$actor->id.'/'.$draftKey.'/'.$imageKey.'-'.$sha.'.'.$extension,
                'status'=>'pending','signed_until'=>now()->addMinutes(110),
                'purge_after'=>now()->addHours(26),
            ]);
        });
        // The server key is used only in CloudAssetStorageService.
        // Never return credentials or a token until an owned pending intent exists.
        return $this->cloud->createPrivateResumableTicket($intent->path)
            + ['expires_at'=>$intent->signed_until->toIso8601String()];
    }

    public function finalize(User $actor, string $draftKey, string $imageKey, int $revision): array
    {
        abort_unless(config('listing_media.resumable_uploads_enabled', false), 404);
        $result = DB::transaction(function () use ($actor, $draftKey, $imageKey, $revision) {
            User::query()->lockForUpdate()->findOrFail($actor->id);
            $draft = $this->drafts->owned($actor, $draftKey, true);
            $this->drafts->assertEditable($actor, $draft->property_id ? Property::findOrFail($draft->property_id) : null);
            $intent = ListingImageUploadIntent::query()->where('listing_editor_draft_id', $draft->id)
                ->where('user_id', $actor->id)->where('image_key', $imageKey)->lockForUpdate()->firstOrFail();
            if ($intent->status === 'complete' && ($draft->images[$imageKey] ?? null) === $intent->path) {
                return $draft;
            }
            abort_unless($intent->status === 'pending' && $intent->signed_until->isFuture(), 409);
            abort_unless(in_array($imageKey, $draft->payload['image_order'] ?? [], true), 409);
            abort_if(isset($draft->images[$imageKey]), 409);
            $this->drafts->assertRevision($draft, $revision);
            $this->images->finalizeResumablePrivate($intent->path, $intent->sha256, $intent->byte_length, $intent->mime);
            $images = $draft->images; $images[$imageKey] = $intent->path;
            $draft->images = $images; $draft->revision++; $draft->save();
            $intent->status = 'complete'; $intent->save();
            return $draft;
        });
        return $this->drafts->present($result);
    }
}
