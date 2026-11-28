<?php

use App\Http\Controllers\Api\GeneralManagerDashboardController;
use App\Http\Controllers\Api\GeneralManagerInsightsController;
use App\Http\Controllers\Api\GeneralManagerOperationsController;
use App\Http\Controllers\Api\SupportTeamController;
use App\Http\Controllers\Api\SupportStaffMessageController;
use App\Http\Controllers\Api\SupportWorkspaceController;
use Illuminate\Support\Facades\Route;

Route::get('/dashboard', [SupportWorkspaceController::class, 'dashboard']);
Route::get('/team-statistics', [SupportWorkspaceController::class, 'statistics']);
Route::get('/general-manager/insights', GeneralManagerDashboardController::class);
Route::get('/general-manager/operations', [GeneralManagerOperationsController::class, 'overview']);
Route::get('/general-manager/decisions', [GeneralManagerOperationsController::class, 'decisions']);
Route::get('/general-manager/decisions/{task}', [GeneralManagerOperationsController::class, 'decision'])->whereNumber('task');
Route::post('/general-manager/decisions/{task}/resolve', [GeneralManagerOperationsController::class, 'resolve'])->whereNumber('task');
Route::get('/general-manager/team', [GeneralManagerInsightsController::class, 'team']);
Route::get('/general-manager/place-search', [GeneralManagerInsightsController::class, 'placeSearch']);
Route::get('/tasks', [SupportWorkspaceController::class, 'index']);
Route::get('/staff-messages', [SupportStaffMessageController::class, 'index']);
Route::post('/staff-messages', [SupportStaffMessageController::class, 'open'])->middleware('throttle:30,1,staff-message-open');
Route::get('/staff-messages/{threadId}', [SupportStaffMessageController::class, 'show'])->whereNumber('threadId');
Route::post('/staff-messages/{threadId}', [SupportStaffMessageController::class, 'send'])
    ->whereNumber('threadId')->middleware('throttle:60,1,staff-message-send');
Route::get('/support-messages', [SupportWorkspaceController::class, 'messages']);
Route::get('/tasks/{taskId}', [SupportWorkspaceController::class, 'show'])->whereNumber('taskId');
Route::post('/tasks/{task}/claim', [SupportWorkspaceController::class, 'claim']);
Route::post('/tasks/{task}/release', [SupportWorkspaceController::class, 'release']);
Route::put('/tasks/{task}/assign', [SupportWorkspaceController::class, 'assign']);
Route::patch('/tasks/{task}/classification', [SupportWorkspaceController::class, 'classify']);
Route::patch('/tasks/{task}/operational-status', [SupportWorkspaceController::class, 'operationalStatus']);
Route::post('/tasks/{task}/escalate', [SupportWorkspaceController::class, 'escalate']);
Route::post('/tasks/{task}/forward-to-executive', [SupportWorkspaceController::class, 'forwardToExecutive']);
Route::post('/tasks/{task}/resolve-escalation', [SupportWorkspaceController::class, 'resolveEscalation']);
Route::post('/tasks/{task}/reopen', [SupportWorkspaceController::class, 'reopen']);
Route::post('/tasks/{task}/request-documents', [SupportWorkspaceController::class, 'requestDocuments']);
Route::post('/tasks/{task}/reject-verification', [SupportWorkspaceController::class, 'rejectVerification']);
Route::get('/tasks/{task}/events', [SupportWorkspaceController::class, 'events']);
Route::get('/team', [SupportWorkspaceController::class, 'team']);
Route::get('/teams', [SupportWorkspaceController::class, 'teams']);
Route::get('/teams/candidates', [SupportTeamController::class, 'candidates'])
    ->middleware(['permission:users.view', 'permission:users.manage_roles', 'throttle:30,1,team-candidates']);
Route::get('/teams/governorates', [SupportTeamController::class, 'governorates'])->middleware('permission:users.manage_roles');
Route::post('/teams', [SupportTeamController::class, 'store'])->middleware('permission:users.manage_roles');
Route::get('/teams/{team}/members', [SupportTeamController::class, 'members'])
    ->whereNumber('team')->middleware('permission:users.manage_roles');
Route::put('/teams/{team}/membership/{user}', [SupportTeamController::class, 'setMember'])
    ->whereNumber(['team', 'user'])->middleware(['permission:users.manage_roles', 'permission:users.manage_permissions']);
Route::put('/team/members/{user}', [SupportWorkspaceController::class, 'updateMember']);
Route::post('/team/members/{user}/redistribute', [SupportWorkspaceController::class, 'redistributeMember']);
