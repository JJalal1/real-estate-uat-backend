<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Services\PropertyMarketContextService;
use Illuminate\Http\JsonResponse;

class PropertyMarketContextController extends Controller
{
    public function __construct(private readonly PropertyMarketContextService $market) {}

    public function show(Property $property): JsonResponse
    {
        abort_unless($property->status === 'published', 404);
        return response()->json(['data' => $this->market->contextFor($property)]);
    }
}
