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

    public function rentalConditions(Request $request, GeminiClient $client, \App\Services\RentalConditionService $conditions): JsonResponse
    {
        $this->advertiser($request);
        $request->validate(['rental_conditions' => ['required'], 'property_id' => ['nullable', 'integer', 'min:1']]);
        $rows = $conditions->normalize($request->input('rental_conditions'));
        abort_if($rows === [], 422, 'اختر شروط الإيجار أولًا.');
        $sentences = $conditions->sentences($rows);
        $result = $client->object('Order the supplied rental requirements for a clear Arabic listing. '
            .'Return every index exactly once. Do not add, rewrite, remove or change requirements or amounts.',
            ['requirements' => $sentences], ['type' => 'object', 'additionalProperties' => false,
                'properties' => ['order' => ['type' => 'array', 'minItems' => count($rows), 'maxItems' => count($rows),
                    'items' => ['type' => 'integer', 'minimum' => 0, 'maximum' => count($rows) - 1]]], 'required' => ['order']]);
        $order = $result['order'] ?? null;
        if (array_keys($result) !== ['order'] || ! is_array($order) || count($order) !== count($rows)) $client->unavailable();
        $sorted = $order; sort($sorted);
        if ($sorted !== range(0, count($rows) - 1)) $client->unavailable();
        $ordered = array_map(fn ($i) => $rows[$i], $order);
        return response()->json(['data' => ['rental_conditions' => $ordered,
            'text' => implode('، ', $conditions->sentences($ordered)).'.', 'requires_review' => true]]);
    }

    public function draft(Request $request, ListingDraftService $service, ListingAiService $listing): JsonResponse
    {
        $this->advertiser($request);
        $v = $request->validate(['mode' => ['required', 'in:prepare,copy'],
            'message' => ['required_if:mode,prepare', 'nullable', 'string', 'max:1500'],
            'facts' => ['present', 'array'], 'property_id' => ['nullable', 'integer', 'min:1']]);
        $facts = $listing->facts($v['facts']);
        $result = $v['mode'] === 'copy' ? $service->copy($facts) : $service->prepare(trim($v['message']), $facts);
        return response()->json(['data' => $result])->header('Cache-Control', 'no-store');
    }

    public function extract(Request $request, ListingAiService $service): JsonResponse
    {
        $this->advertiser($request);
        $v = $request->validate(['message' => ['required', 'string', 'max:1500'], 'facts' => ['present', 'array'],
            'property_id' => ['nullable', 'integer', 'min:1']]);
        return response()->json(['data' => $service->extract($v['message'], $service->facts($v['facts']))]);
    }

    public function description(Request $request, ListingAiService $service): JsonResponse
    {
        $this->advertiser($request);
        $v = $request->validate(['facts' => ['required', 'array'], 'property_id' => ['nullable', 'integer', 'min:1']]);
        return response()->json(['data' => $service->description($service->facts($v['facts']))]);
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
