<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Services\GeminiClient;
use App\Services\ListingAccessService;
use App\Services\ListingAiService;
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
        $v = $request->validate(['message' => ['required', 'string', 'max:1000'], 'filters' => ['present', 'array'],
            'revision' => ['required', 'integer', 'between:0,1000000000']]);
        $result = $service->update($v['message'], $v['filters']);
        $result['filters'] = (object) $result['filters'];
        $result['revision'] = $v['revision'];
        return response()->json(['data' => $result]);
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
            app(ListingAccessService::class)->assertCanCreate($actor);
        }
    }
}
