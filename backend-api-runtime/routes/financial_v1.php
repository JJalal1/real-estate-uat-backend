<?php

use App\Http\Controllers\Api\FinancialPropertyController;
use App\Http\Controllers\Api\PropertyFinancialController;
use Illuminate\Support\Facades\Route;

// Re-declare public property reads after routes/api.php so Financial V1 is
// authoritative for price display and overdue financial visibility.
Route::get('/properties', [FinancialPropertyController::class, 'index']);
Route::get('/properties/nearby', [FinancialPropertyController::class, 'nearby']);
Route::get('/properties/{property}', [FinancialPropertyController::class, 'show']);

Route::middleware(['auth.api', 'account.active'])->group(function (): void {
    // Financial V1 is authoritative for listing mutations. The inherited
    // PropertyController behavior stays intact underneath this thin layer.
    Route::get('/properties/mine/list', [FinancialPropertyController::class, 'mine']);
    Route::post('/properties', [FinancialPropertyController::class, 'store']);
    Route::post('/properties/{property}', [FinancialPropertyController::class, 'update']);
    Route::post('/properties/{property}/submit', [FinancialPropertyController::class, 'submit']);

    Route::get('/finance/payments/mine', [PropertyFinancialController::class, 'paymentsMine']);
    Route::get('/finance/account', [PropertyFinancialController::class, 'financialAccount']);
    Route::get('/finance/agreements/{agreement}', [PropertyFinancialController::class, 'deal']);
    Route::post('/finance/agreements/{agreement}/payments', [PropertyFinancialController::class, 'createPayment']);
    Route::post('/finance/agreements/{agreement}/direct-confirmation', [PropertyFinancialController::class, 'confirmDirect']);
    Route::post('/finance/receivables/{receivable}/payments', [PropertyFinancialController::class, 'createReceivablePayment']);
    Route::post('/finance/payments/{payment}/proof', [PropertyFinancialController::class, 'submitProof'])->middleware('throttle:8,1');
    Route::get('/finance/payments/{payment}/proof', [PropertyFinancialController::class, 'proof']);
    Route::post('/properties/{property}/sai-attestation', [PropertyFinancialController::class, 'attestSai']);

    Route::get('/admin/finance/summary', [PropertyFinancialController::class, 'adminSummary'])->middleware('permission:finance.view');
    Route::get('/admin/finance/payment-methods', [PropertyFinancialController::class, 'adminPaymentMethods'])->middleware('permission:finance.manage');
    Route::patch('/admin/finance/payment-methods/{method}', [PropertyFinancialController::class, 'updatePaymentMethod'])->middleware('permission:finance.manage');
    Route::post('/admin/finance/payments/{payment}/review', [PropertyFinancialController::class, 'review'])->middleware('permission:payments.review');
    Route::post('/admin/finance/payouts/{payout}/paid', [PropertyFinancialController::class, 'recordPayout'])->middleware('permission:finance.manage');
});
