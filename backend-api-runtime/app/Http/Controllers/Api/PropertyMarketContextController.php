<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Property;
use App\Services\PropertyMarketContextService;
use Illuminate\Http\JsonResponse;

class PropertyMarketContextController extends Controller
{
    public function __construct(private readonly PropertyMarketContextService $market) {}

    public function show(int $property): JsonResponse
    {
        $row = Property::query()
            ->whereKey($property)
            ->where('status', 'published')
            ->firstOrFail();

        return response()->json(['data' => $this->market->contextFor($row)]);
    }
}
