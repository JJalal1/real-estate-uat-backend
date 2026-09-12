<?php

use App\Http\Controllers\Api\FinancialAgreementContractController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth.api', 'account.active'])->group(function (): void {
    Route::get('/agreements/mine', [FinancialAgreementContractController::class, 'agreementsMine']);
    Route::post('/messages/threads/{thread}/agreement', [FinancialAgreementContractController::class, 'startAgreement']);
    Route::get('/agreements/{agreement}', [FinancialAgreementContractController::class, 'agreementShow']);
    Route::post('/agreements/{agreement}/revisions', [FinancialAgreementContractController::class, 'reviseAgreement']);
    Route::post('/agreements/{agreement}/accept', [FinancialAgreementContractController::class, 'acceptAgreement']);
    Route::post('/agreements/{agreement}/cancel', [FinancialAgreementContractController::class, 'cancelAgreement']);

    Route::get('/rental-contracts/mine', [FinancialAgreementContractController::class, 'contractsMine']);
    Route::post('/agreements/{agreement}/rental-contract', [FinancialAgreementContractController::class, 'startRentalContract']);
    Route::get('/rental-contracts/{contract}', [FinancialAgreementContractController::class, 'contractShow']);
    Route::post('/rental-contracts/{contract}/revisions', [FinancialAgreementContractController::class, 'reviseRentalContract']);
    Route::post('/rental-contracts/{contract}/accept', [FinancialAgreementContractController::class, 'acceptRentalContract']);
    Route::post('/rental-contracts/{contract}/cancel', [FinancialAgreementContractController::class, 'cancelRentalContract']);
    Route::post('/rental-contracts/{contract}/terminate', [FinancialAgreementContractController::class, 'terminateRentalContract']);
});
