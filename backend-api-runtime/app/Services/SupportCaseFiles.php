<?php

namespace App\Services;

use App\Models\SupportCase;
use App\Models\SupportCaseMessage;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class SupportCaseFiles
{
    public const RULES = ['nullable', 'file', 'mimes:jpg,jpeg,png,webp,pdf', 'max:8192'];

    public function __construct(private readonly CloudAssetStorageService $storage) {}

    /**
     * The operation returns the message that owns the file. Any failed
     * database write removes the new private object.
     */
    public function withUpload(?UploadedFile $file, callable $operation): SupportCase
    {
        if (!$file) return DB::transaction(fn () => $operation()[0]);
        $path = $this->storage->storePrivate($file, 'support-evidence');
        try {
            return DB::transaction(function () use ($file, $path, $operation): SupportCase {
                [$case, $message] = $operation();
                if ($message === null) {
                    $this->storage->deletePrivate($path);

                    return $case;
                }
                DB::table('support_case_files')->insert([
                    'support_case_message_id' => $message->id,
                    'private_path' => $path,
                    'name' => mb_substr(basename($file->getClientOriginalName()), 0, 180),
                    'mime' => $file->getMimeType(),
                ]);

                return $case;
            });
        } catch (\Throwable $error) {
            $this->storage->deletePrivate($path);
            throw $error;
        }
    }

    public function lastMessage(SupportCase $case): SupportCaseMessage
    {
        return SupportCaseMessage::query()->where('support_case_id', $case->id)->latest('id')->firstOrFail();
    }

    public function forMessages(array $messageIds): array
    {
        return DB::table('support_case_files')->whereIn('support_case_message_id', $messageIds)
            ->orderBy('id')->get(['id', 'support_case_message_id', 'name', 'mime'])
            ->groupBy('support_case_message_id')
            ->map(fn ($files) => $files->map(fn ($file) => [
                'id' => (int) $file->id, 'name' => $file->name, 'mime' => $file->mime,
            ])->all())->all();
    }

    public function response(SupportCase $case, int $fileId, bool $staff): Response
    {
        $file = DB::table('support_case_files as f')
            ->join('support_case_messages as m', 'm.id', '=', 'f.support_case_message_id')
            ->where('f.id', $fileId)->where('m.support_case_id', $case->id)
            ->when(!$staff, fn ($query) => $query->where('m.is_internal', false))
            ->first(['f.private_path', 'f.name', 'f.mime']);
        abort_if(!$file, 404);
        $headers = ['Cache-Control' => 'private, no-store', 'X-Content-Type-Options' => 'nosniff', 'Content-Type' => $file->mime];

        return $file->mime === 'application/pdf'
            ? $this->storage->downloadPrivate($file->private_path, $file->name, $headers)
            : $this->storage->responsePrivate($file->private_path, null, $headers);
    }
}
