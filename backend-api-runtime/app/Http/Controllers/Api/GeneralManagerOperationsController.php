<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportTask;
use App\Models\UserNotification;
use App\Services\SupportTaskService;
use App\Services\SupportTeamStatistics;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class GeneralManagerOperationsController extends Controller
{
    public function overview(Request $request, SupportTeamStatistics $statistics): JsonResponse
    {
        $this->authorizeExecutive($request);
        $filters = $request->validate([
            'period' => ['nullable', Rule::in(['day', '7d', '30d'])],
            'governorate_id' => ['nullable', 'integer', 'exists:governorates,id'],
        ]);
        $period = $filters['period'] ?? 'day';
        $province = isset($filters['governorate_id']) ? (int) $filters['governorate_id'] : null;
        $end = CarbonImmutable::now('Asia/Aden')->startOfDay();
        $start = $end->subDays(match ($period) { '7d' => 6, '30d' => 29, default => 0 });
        $result = $statistics->forExecutive($request->user(), $start->toDateString(), $end->toDateString(), $province);
        $result['decisions'] = $this->pendingDecisions($province)->count();
        $result['unread_messages'] = UserNotification::query()->where('user_id', $request->user()->id)
            ->where('entity_type', 'support_staff_thread')->whereNull('read_at')->count();
        $result['journey'] = [];
        foreach ([
            'conversations' => ['message_threads', 'property_id'],
            'viewings' => ['viewing_bookings', 'target_id'],
            'agreements' => ['property_agreements', 'property_id'],
            'rental_contracts' => ['rental_contracts', 'property_id'],
        ] as $key => [$table, $propertyKey]) {
            $query = DB::table($table)->where('created_at', '>=', $start->utc())
                ->where('created_at', '<', $end->addDay()->utc());
            if ($province !== null) {
                if ($key === 'viewings') $query->where('target_type', 'property');
                $query->whereIn($propertyKey, $statistics->provinceProperties([$province])->select('id'));
            }
            $result['journey'][$key] = $query->count();
        }

        return response()->json(['data' => $result]);
    }

    public function decision(Request $request, SupportTask $task, SupportTaskService $tasks): JsonResponse
    {
        $this->authorizeExecutive($request);
        abort_if($task->source_type === 'contact_followup', 404);

        return response()->json(['data' => $tasks->taskData($task, $request->user())]);
    }

    public function resolve(Request $request, SupportTask $task, SupportTaskService $tasks): JsonResponse
    {
        $this->authorizeExecutive($request);
        $input = $request->validate(['note' => ['required', 'string', 'min:3', 'max:1200']]);
        $task = $tasks->resolveEscalation($request->user(), $task, trim($input['note']), $request, executiveOnly: true);

        return response()->json(['data' => $tasks->taskData($task, $request->user())]);
    }

    public function decisions(Request $request, SupportTaskService $tasks): JsonResponse
    {
        $this->authorizeExecutive($request);
        $filters = $request->validate(['governorate_id' => ['nullable', 'integer', 'exists:governorates,id']]);
        $province = isset($filters['governorate_id']) ? (int) $filters['governorate_id'] : null;
        $page = $this->pendingDecisions($province)->with(['team:id,name_ar', 'governorate:id,name_ar'])
            ->latest('escalated_at')->latest('id')->paginate(25);

        return response()->json([
            'data' => collect($page->items())->map(fn (SupportTask $task) => $tasks->taskData($task, $request->user())),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }

    private function pendingDecisions(?int $province): Builder
    {
        return SupportTask::query()->where('status', 'escalated')->whereNotNull('metadata->executive_escalation')
            ->when($province, fn ($query) => $query->where('governorate_id', $province));
    }

    private function authorizeExecutive(Request $request): void
    {
        $actor = $request->user();
        abort_unless($actor?->isActive() && ($actor->is_platform_owner || $actor->hasRole('super_admin')), 403);
    }
}
