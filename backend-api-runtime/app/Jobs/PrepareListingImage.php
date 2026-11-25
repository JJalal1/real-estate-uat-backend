<?php

namespace App\Jobs;

use App\Models\ListingEditorDraft;
use App\Models\PropertyImage;
use App\Services\ListingImageService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

class PrepareListingImage implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public int $ownerRow, public string $pathHash, public ?string $draftImageKey = null,
    ) {}

    public function handle(ListingImageService $images): void
    {
        // Serialize with replacement/deletion. Never load an object path from the queue.
        DB::transaction(function () use ($images) {
            if ($this->draftImageKey !== null) {
                $draft = ListingEditorDraft::query()->lockForUpdate()->find($this->ownerRow);
                $path = $draft?->images[$this->draftImageKey] ?? null;
            } else {
                $path = PropertyImage::query()->lockForUpdate()->find($this->ownerRow)?->path;
            }
            if ($path && hash_equals($this->pathHash, hash('sha256', $path))) $images->prepareVariants($path);
        });
    }
}
