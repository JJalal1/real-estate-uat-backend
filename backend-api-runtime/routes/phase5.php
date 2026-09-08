<?php

use App\Http\Controllers\Api\AgreementContractController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth.api', 'account.active'])->group(function (): void {
    Route::get('/agreements/mine', [AgreementContractController::class, 'agreementsMine']);
    Route::post('/messages/threads/{thread}/agreement', [AgreementContractController::class, 'startAgreement']);
    Route::get('/agreements/{agreement}', [AgreementContractController::class, 'agreementShow']);
    Route::post('/agreements/{agreement}/revisions', [AgreementContractController::class, 'reviseAgreement']);
    Route::post('/agreements/{agreement}/accept', [AgreementContractController::class, 'acceptAgreement']);
    Route::post('/agreements/{agreement}/cancel', [AgreementContractController::class, 'cancelAgreement']);

    Route::get('/rental-contracts/mine', [AgreementContractController::class, 'contractsMine']);
    Route::post('/agreements/{agreement}/rental-contract', [AgreementContractController::class, 'startRentalContract']);
    Route::get('/rental-contracts/{contract}', [AgreementContractController::class, 'contractShow']);
    Route::post('/rental-contracts/{contract}/revisions', [AgreementContractController::class, 'reviseRentalContract']);
    Route::post('/rental-contracts/{contract}/accept', [AgreementContractController::class, 'acceptRentalContract']);
    Route::post('/rental-contracts/{contract}/cancel', [AgreementContractController::class, 'cancelRentalContract']);
    Route::post('/rental-contracts/{contract}/terminate', [AgreementContractController::class, 'terminateRentalContract']);
});
