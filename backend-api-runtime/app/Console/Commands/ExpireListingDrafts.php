<?php

namespace App\Console\Commands;

use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\User;
use App\Services\ListingEditorDraftService;
use App\Services\PropertyIdentityService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ExpireListingDrafts extends Command
{
    protected $signature = 'listings:expire-drafts';
    protected $description = 'Remove expired private drafts and release their unshared media.';

    public function handle(ListingEditorDraftService $drafts, PropertyIdentityService $identity): int
    {
        $cutoff = now()->subDays(7);
        // Only properties that have never been submitted carry an expiry.
        Property::withoutGlobalScope('unexpired_drafts')->where('draft_expires_at', '<=', now())
            ->select('id', 'user_id')->chunkById(100, function ($properties) use ($drafts, $identity): void {
                foreach ($properties as $candidate) {
                    DB::transaction(function () use ($candidate, $drafts, $identity): void {
                        $actor = User::query()->lockForUpdate()->find($candidate->user_id);
                        if (!$actor) return;
                        $property = Property::withoutGlobalScope('unexpired_drafts')->where('draft_expires_at', '<=', now())
                            ->whereKey($candidate->id)->lockForUpdate()->first();
                        if (!$property) return;
                        if ($property->status !== 'draft' || $property->review_status !== 'draft' || $property->first_listed_at
                            || $property->published_at || $property->submitted_at || $property->reviewed_at || $property->reviews()->exists()) {
                            $property->forceFill(['draft_expires_at'=>null])->save();
                            return;
                        }

                        $attached = ListingEditorDraft::where('property_id', $property->id)->lockForUpdate()->get();
                        $journal = $attached->shift() ?? new ListingEditorDraft([
                            'user_id'=>$actor->id, 'client_key'=>(string)Str::uuid(), 'images'=>[], 'revision'=>0, 'payload'=>[],
                        ]);
                        $drafts->retire($journal, $property->images()->pluck('path')->filter()->all(),
                            $property->documents()->pluck('path')->filter()->all());
                        foreach ($attached as $draft) $drafts->retire($draft);
                        $identity->releaseRepresentationForListing($property, 'draft_expired');
                        $property->delete();
                    });
                }
            });

        ListingEditorDraft::query()->where('created_at', '<=', $cutoff)
            ->where(fn ($q) => $q->whereNull('payload->draft_kind')->orWhere('payload->draft_kind', '!=', 'retired'))
            ->select('id', 'user_id')->chunkById(100, function ($rows) use ($drafts): void {
                foreach ($rows as $candidate) {
                    DB::transaction(function () use ($candidate, $drafts): void {
                        User::query()->lockForUpdate()->find($candidate->user_id);
                        $draft = ListingEditorDraft::query()->lockForUpdate()->find($candidate->id);
                        if ($draft && ($draft->payload['draft_kind'] ?? null) !== 'retired') $drafts->retire($draft);
                    });
                }
            });

        $failed = false;
        ListingEditorDraft::where('payload->draft_kind', 'retired')
            ->where(fn ($q) => $q->whereNotNull('payload->cleanup_paths')->orWhereNotNull('payload->cleanup_documents'))
            ->chunkById(100, function ($rows) use ($drafts, &$failed): void {
                foreach ($rows as $row) {
                    try {
                        $drafts->cleanRetiredMedia($row);
                    } catch (\Throwable $error) {
                        report($error);
                        $failed = true;
                    }
                }
            });
        return $failed ? self::FAILURE : self::SUCCESS;
    }
}
