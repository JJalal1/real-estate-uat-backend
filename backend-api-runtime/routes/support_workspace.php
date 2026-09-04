<?php

use App\Http\Controllers\Api\SupportWorkspaceController;
use Illuminate\Support\Facades\Route;

Route::get('/dashboard', [SupportWorkspaceController::class, 'dashboard']);
Route::get('/tasks', [SupportWorkspaceController::class, 'index']);
Route::post('/tasks/{task}/claim', [SupportWorkspaceController::class, 'claim']);
Route::put('/tasks/{task}/assign', [SupportWorkspaceController::class, 'assign']);
Route::patch('/tasks/{task}/classification', [SupportWorkspaceController::class, 'classify']);
Route::patch('/tasks/{task}/operational-status', [SupportWorkspaceController::class, 'operationalStatus']);
Route::post('/tasks/{task}/escalate', [SupportWorkspaceController::class, 'escalate']);
Route::post('/tasks/{task}/reopen', [SupportWorkspaceController::class, 'reopen']);
Route::post('/tasks/{task}/request-documents', [SupportWorkspaceController::class, 'requestDocuments']);
Route::post('/tasks/{task}/reject-verification', [SupportWorkspaceController::class, 'rejectVerification']);
Route::get('/tasks/{task}/events', [SupportWorkspaceController::class, 'events']);
Route::get('/team', [SupportWorkspaceController::class, 'team']);
