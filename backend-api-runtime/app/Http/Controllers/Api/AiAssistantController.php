<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Services\GeminiClient;
use App\Services\ListingAccessService;
use App\Services\ListingAiService;
use App\Services\ListingDraftService;
use App\Services\SmartSearchService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AiAssistantController extends Controller
{
    public function capabilities(GeminiClient $client): JsonResponse
    {
        return response()->json(['data' => ['available' => $client->available(), 'manual_filters_available' => true]]);
    }

    public function search(Request $request, SmartSearchService $service): JsonResponse
    {
        $v = $request->validate(['message' => ['required', 'string', 'max:5000'], 'filters' => ['present', 'array'],
            'revision' => ['required', 'integer', 'between:0,1000000000']]);
        $result = $service->update($v['message'], $v['filters']);
        $result['filters'] = (object) $result['filters'];
        $result['revision'] = $v['revision'];
        return response()->json(['data' => $result]);
    }

    public function transcribe(Request $request, GeminiClient $client): JsonResponse
    {
        $request->validate(['audio' => ['required', 'file', 'max:8192']]);
        $audio = $request->file('audio');
        abort_unless(in_array($audio->getMimeType(), ['audio/mp4', 'audio/x-m4a', 'video/mp4'], true), 422, 'ملف الصوت غير مدعوم.');
        // The PHP request temporary upload is not copied to Storage or logs.
        $bytes = file_get_contents($audio->getRealPath());
        abort_unless(is_string($bytes) && str_contains(substr($bytes, 0, 64), 'ftyp'), 422, 'ملف الصوت غير صالح.');
        return response()->json(['data' => ['transcript' => $client->transcribe($bytes), 'complete' => true]])
            ->header('Cache-Control', 'no-store');
    }

    public function rentalConditions(Request $request): JsonResponse
    {
        $this->advertiser($request);
        return response()->json(['message'=>'أضف شروط الإيجار يدويًا من الخيارات المتاحة.',
            'code'=>'RENTAL_CONDITIONS_AI_RETIRED'], 410);
    }

    public function draft(Request $request, ListingDraftService $service, ListingAiService $listing): JsonResponse
    {
        $this->advertiser($request);
        $v = $request->validate(['mode' => ['required', 'in:prepare,copy'],
            'message' => ['required_if:mode,prepare', 'nullable', 'string', 'max:5000'],
            'facts' => ['present', 'array'], 'property_id' => ['nullable', 'integer', 'min:1']]);
        $facts = $listing->facts($v['facts']);
        $result = $v['mode'] === 'copy' ? $service->copy($facts) : $service->prepare(trim($v['message']), $facts);
        return response()->json(['data' => $result])->header('Cache-Control', 'no-store');
    }

    public function extract(Request $request, ListingAiService $service): JsonResponse
    {
        $this->advertiser($request);
        $v = $request->validate(['message' => ['required', 'string', 'max:5000'], 'facts' => ['present', 'array'],
            'property_id' => ['nullable', 'integer', 'min:1']]);
        return response()->json(['data' => $service->extract($v['message'], $service->facts($v['facts']))]);
    }

    public function description(Request $request, ListingAiService $service): JsonResponse
    {
        $this->advertiser($request);
        $v = $request->validate(['facts' => ['present', 'array'], 'description' => ['nullable','string','max:5000'],
            'property_id' => ['nullable', 'integer', 'min:1']]);
        return response()->json(['data' => $service->description($service->facts($v['facts']), $v['description'] ?? '')]);
    }

    public function question(Request $request, Property $property, ListingAiService $service): JsonResponse
    {
        abort_unless($property->isPubliclyAvailable(), 404);
        abort_if(app(\App\Services\PropertyFinancialService::class)->hasOverdueReceivable((int) $property->user_id), 404);
        $v = $request->validate(['question' => ['required', 'string', 'max:800']]);
        return response()->json(['data' => $service->question($property, $v['question'])]);
    }

    private function advertiser(Request $request): void
    {
        $actor = $request->user();
        abort_unless($actor && $actor->isActive() && $actor->hasApprovedVerificationProfile() && $actor->canCreateListings(), 403);
        $id = $request->input('property_id');
        if ($id !== null) {
            $request->validate(['property_id' => ['integer', 'min:1']]);
            $property = Property::query()->withoutGlobalScopes()->findOrFail($id);
            abort_unless((int) $property->user_id === (int) $actor->id, 404);
            abort_unless(! in_array($property->review_status, ['submitted', 'under_review', 'rejected_blocked'], true), 409);
        } else {
            app(ListingAccessService::class)->assertCanCreate($actor,$request->input('editor_draft_key'));
            if ($request->input('editor_draft_key')) {
                $request->validate(['editor_draft_key'=>['uuid']]);
                $draft=app(\App\Services\ListingEditorDraftService::class)->owned($actor,$request->input('editor_draft_key'));
                if ($draft->property_id) app(\App\Services\ListingEditorDraftService::class)->assertEditable($actor,Property::query()->findOrFail($draft->property_id));
            }
        }
    }
}
