<?php
use App\Http\Controllers\Api\AccessControlController;
use App\Http\Controllers\Api\AccountVerificationController;
use App\Http\Controllers\Api\AdminWorkspaceController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\BrokerAccountVerificationController;
use App\Http\Controllers\Api\CommunityController;
use App\Http\Controllers\Api\DevelopmentController;
use App\Http\Controllers\Api\FreeServicesHubController;
use App\Http\Controllers\Api\ListingReviewController;
use App\Http\Controllers\Api\MessagingController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\PropertyController;
use App\Http\Controllers\Api\PropertyRequestController;
use App\Http\Controllers\Api\RegionsController;
use App\Http\Controllers\Api\SupportController;
use App\Http\Controllers\Api\ServicePaymentController;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    try {
        DB::select('select 1');
        $postgis = true;

        if (DB::connection()->getDriverName() === 'pgsql') {
            $row = DB::selectOne("select count(*)::int as count from pg_extension where extname = 'postgis'");
            $postgis = (int) ($row->count ?? 0) > 0;
        }

        return response()->json([
            'status' => $postgis ? 'ok' : 'degraded',
            'database' => true,
            'postgis' => $postgis,
        ], $postgis ? 200 : 503);
    } catch (\Throwable) {
        return response()->json([
            'status' => 'degraded',
            'database' => false,
            'postgis' => false,
        ], 503);
    }
});

Route::prefix('auth')->group(function () {
    Route::post('/whatsapp/start', [AuthController::class, 'startWhatsApp'])->middleware('throttle:6,1');
    Route::post('/whatsapp/verify', [AuthController::class, 'verifyWhatsApp'])->middleware('throttle:12,1');
    Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:8,1');
    Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:12,1');
    Route::post('/password/forgot', [AuthController::class, 'forgotPassword'])->middleware('throttle:6,1');
    Route::post('/password/reset', [AuthController::class, 'resetPassword'])->middleware('throttle:8,1');

    Route::middleware('auth.api')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/logout', [AuthController::class, 'logout']);
        Route::patch('/profile', [AuthController::class, 'updateProfile']);
        Route::post('/phone/request', [AuthController::class, 'requestPhoneVerification'])->middleware('throttle:6,1');
        Route::post('/phone/verify', [AuthController::class, 'verifyPhone'])->middleware('throttle:12,1');
        Route::post('/legacy/claim', [AuthController::class, 'claimLegacyOwnership'])->middleware('throttle:6,1');
    });
});

Route::get('/properties', [PropertyController::class, 'index']);
Route::get('/properties/nearby', [PropertyController::class, 'nearby']);
Route::get('/properties/{property}/comments', [CommunityController::class, 'comments']);
Route::get('/properties/{property}', [PropertyController::class, 'show']);
Route::get('/property-media/{image}', [PropertyController::class, 'media']);
Route::get('/advertisers/{advertiser}/ratings/summary', [CommunityController::class, 'ratingSummary']);
Route::get('/regions/cells', [RegionsController::class, 'publicCells']);
Route::get('/regions/resolve', [RegionsController::class, 'resolvePoint']);
Route::get('/regions/reverse-address', [RegionsController::class, 'reverseAddress']);
Route::get('/developers', [DevelopmentController::class, 'developers']);
Route::get('/developers/{developer}', [DevelopmentController::class, 'developerShow']);
Route::get('/developments', [DevelopmentController::class, 'index']);
Route::get('/developments/{development}', [DevelopmentController::class, 'show']);
Route::get('/services/catalog', [ServicePaymentController::class, 'catalog']);
Route::get('/properties/{property}/services', [ServicePaymentController::class, 'propertyServices']);

Route::middleware(['auth.api', 'account.active'])->group(function () {
    Route::get('/services/hub', [FreeServicesHubController::class, 'show']);
    Route::get('/property-requests', [PropertyRequestController::class, 'index']);
    Route::post('/property-requests', [PropertyRequestController::class, 'store']);
    Route::get('/property-requests/{propertyRequest}', [PropertyRequestController::class, 'show']);
    Route::patch('/property-requests/{propertyRequest}', [PropertyRequestController::class, 'update']);
    Route::post('/property-requests/{propertyRequest}/close', [PropertyRequestController::class, 'close']);
    Route::get('/researcher-requests', [PropertyRequestController::class, 'researcherIndex']);
    Route::get('/researcher-requests/{propertyRequest}', [PropertyRequestController::class, 'researcherShow']);
    Route::post('/researcher-requests/{propertyRequest}/suggestions', [PropertyRequestController::class, 'suggest']);
    Route::get('/properties/mine/list', [PropertyController::class, 'mine']);
    Route::post('/properties', [PropertyController::class, 'store']);
    Route::post('/properties/{property}', [PropertyController::class, 'update']);
    Route::delete('/properties/{property}', [PropertyController::class, 'destroy']);
    Route::post('/properties/{property}/submit', [PropertyController::class, 'submit']);
    Route::post('/properties/{property}/proof-documents', [PropertyController::class, 'uploadProofDocuments']);
    Route::delete('/properties/{property}/proof-documents/{document}', [PropertyController::class, 'deleteProofDocument']);
    Route::get('/listing-documents/{document}', [ListingReviewController::class, 'document']);

    Route::get('/account-verification', [AccountVerificationController::class, 'status']);
    Route::post('/account-verification', [AccountVerificationController::class, 'submit'])->middleware('throttle:4,1');
    Route::get('/account-verification/users/{user}/documents/{kind}', [AccountVerificationController::class, 'document']);

    Route::get('/broker/account-verification', [BrokerAccountVerificationController::class, 'status']);
    Route::post('/broker/account-verification', [BrokerAccountVerificationController::class, 'submit'])->middleware('throttle:4,1');
    Route::get('/broker/account-verification/users/{user}/documents/{kind}', [BrokerAccountVerificationController::class, 'document']);

    Route::post('/properties/{property}/comments', [CommunityController::class, 'storeComment']);
    Route::patch('/comments/{comment}', [CommunityController::class, 'updateComment']);
    Route::delete('/comments/{comment}', [CommunityController::class, 'deleteComment']);
    Route::put('/advertisers/{advertiser}/rating', [CommunityController::class, 'upsertRating']);
    Route::delete('/advertisers/{advertiser}/rating', [CommunityController::class, 'deleteRating']);

    Route::post('/reports', [SupportController::class, 'report']);
    Route::get('/support/cases/mine', [SupportController::class, 'mine']);
    Route::post('/support/cases', [SupportController::class, 'storeTicket']);
    Route::get('/support/cases/{case}', [SupportController::class, 'showMine']);
    Route::post('/support/cases/{case}/messages', [SupportController::class, 'replyMine']);



    Route::get('/services/orders/mine', [ServicePaymentController::class, 'mineOrders']);
    Route::get('/services/entitlements/mine', [ServicePaymentController::class, 'mineEntitlements']);
    Route::post('/services/orders', [ServicePaymentController::class, 'createOrder']);
    Route::get('/services/orders/{order}', [ServicePaymentController::class, 'showOrder']);
    Route::post('/services/orders/{order}/cancel', [ServicePaymentController::class, 'cancelOrder']);

    Route::prefix('admin/services')->group(function () {
        Route::get('/offers', [ServicePaymentController::class, 'adminOffers'])->middleware('permission:services.manage');
        Route::post('/offers', [ServicePaymentController::class, 'storeOffering'])->middleware('permission:services.manage');
        Route::patch('/offers/{offering}', [ServicePaymentController::class, 'updateOffering'])->middleware('permission:services.manage');
    });

    Route::prefix('admin/payments')->group(function () {
        Route::get('/orders', [ServicePaymentController::class, 'adminOrders'])->middleware('permission:payments.manage');
        Route::get('/orders/{order}', [ServicePaymentController::class, 'showOrder'])->middleware('permission:payments.manage');
        Route::post('/orders/{order}/settle', [ServicePaymentController::class, 'settle'])->middleware('permission:payments.manage');
        Route::post('/orders/{order}/refund', [ServicePaymentController::class, 'refund'])->middleware('permission:payments.manage');
    });

    Route::get('/bookings/mine', [BookingController::class, 'mine']);
    Route::get('/bookings/managed', [BookingController::class, 'managed']);
    Route::get('/bookings/{booking}', [BookingController::class, 'show']);
    Route::post('/properties/{property}/viewings', [BookingController::class, 'requestForProperty']);
    Route::post('/development-units/{unit}/viewings', [BookingController::class, 'requestForUnit']);
    Route::post('/bookings/{booking}/confirm', [BookingController::class, 'confirm']);
    Route::post('/bookings/{booking}/decline', [BookingController::class, 'decline']);
    Route::post('/bookings/{booking}/cancel', [BookingController::class, 'cancel']);
    Route::post('/bookings/{booking}/reschedule', [BookingController::class, 'reschedule']);
    Route::post('/bookings/{booking}/complete', [BookingController::class, 'complete']);

    Route::get('/messages/threads', [MessagingController::class, 'threads']);
    Route::post('/properties/{property}/conversation', [MessagingController::class, 'startForProperty']);
    Route::get('/messages/threads/{thread}', [MessagingController::class, 'show']);
    Route::post('/messages/threads/{thread}/messages', [MessagingController::class, 'send']);
    Route::post('/messages/threads/{thread}/read', [MessagingController::class, 'markRead']);
    Route::post('/messages/threads/{thread}/report', [MessagingController::class, 'report']);
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('/notifications/read-all', [NotificationController::class, 'readAll']);
    Route::post('/notifications/{notification}/read', [NotificationController::class, 'read']);

    Route::get('/admin/dashboard', [AdminWorkspaceController::class, 'dashboard'])->middleware('permission:dashboard.view');
    Route::get('/admin/settings', [AdminWorkspaceController::class, 'settings'])->middleware('permission:settings.view');
    Route::patch('/admin/settings', [AdminWorkspaceController::class, 'updateSettings'])->middleware('permission:settings.manage');

    Route::prefix('admin/messages')->group(function () {
        Route::get('/reports', [MessagingController::class, 'adminReports'])->middleware('permission:support.handle_reports');
        Route::get('/reports/{report}/content', [MessagingController::class, 'adminOpenReportedContent'])->middleware('permission:conversations.review_private');
        Route::patch('/reports/{report}/resolve', [MessagingController::class, 'adminResolveReport'])->middleware('permission:support.manage');
    });

    Route::prefix('admin/developments')->group(function () {
        Route::get('/developers', [DevelopmentController::class, 'adminDevelopers'])->middleware('permission:developments.manage');
        Route::post('/developers', [DevelopmentController::class, 'storeDeveloper'])->middleware('permission:developments.manage');
        Route::patch('/developers/{developer}', [DevelopmentController::class, 'updateDeveloper'])->middleware('permission:developments.manage');
        Route::get('/projects', [DevelopmentController::class, 'adminProjects'])->middleware('permission:developments.manage');
        Route::post('/projects', [DevelopmentController::class, 'storeProject'])->middleware('permission:developments.manage');
        Route::get('/projects/{development}', [DevelopmentController::class, 'adminProjectShow'])->middleware('permission:developments.manage');
        Route::patch('/projects/{development}', [DevelopmentController::class, 'updateProject'])->middleware('permission:developments.manage');
        Route::post('/projects/{development}/publish', [DevelopmentController::class, 'publish'])->middleware('permission:developments.publish');
        Route::post('/projects/{development}/unpublish', [DevelopmentController::class, 'unpublish'])->middleware('permission:developments.publish');
        Route::post('/projects/{development}/units', [DevelopmentController::class, 'storeUnit'])->middleware('permission:developments.manage');
        Route::patch('/units/{unit}', [DevelopmentController::class, 'updateUnit'])->middleware('permission:developments.manage');
        Route::delete('/units/{unit}', [DevelopmentController::class, 'deleteUnit'])->middleware('permission:developments.manage');
    });

    Route::prefix('admin/community')->group(function () {
        Route::post('/comments/{comment}/hide', [CommunityController::class, 'hideComment'])->middleware('permission:content.moderate');
        Route::post('/comments/{comment}/unhide', [CommunityController::class, 'unhideComment'])->middleware('permission:content.moderate');
        Route::post('/ratings/{rating}/hide', [CommunityController::class, 'hideRating'])->middleware('permission:content.moderate');
        Route::post('/ratings/{rating}/unhide', [CommunityController::class, 'unhideRating'])->middleware('permission:content.moderate');
    });

    Route::prefix('admin/account-verifications')->group(function () {
        Route::get('/', [AccountVerificationController::class, 'adminIndex'])->middleware('permission:accounts.verify_profiles');
        Route::post('/{user}/approve', [AccountVerificationController::class, 'approve'])->middleware('permission:accounts.verify_profiles');
        Route::post('/{user}/more-info', [AccountVerificationController::class, 'requestMoreInfo'])->middleware('permission:accounts.verify_profiles');
        Route::post('/{user}/reject', [AccountVerificationController::class, 'reject'])->middleware('permission:accounts.verify_profiles');
    });

    Route::prefix('admin/broker-account-verifications')->group(function () {
        Route::get('/', [BrokerAccountVerificationController::class, 'adminIndex'])->middleware('permission:brokers.verify_accounts');
        Route::post('/{user}/approve', [BrokerAccountVerificationController::class, 'approve'])->middleware('permission:brokers.verify_accounts');
        Route::post('/{user}/reject', [BrokerAccountVerificationController::class, 'reject'])->middleware('permission:brokers.verify_accounts');
    });

    Route::prefix('admin/support')->group(function () {
        Route::get('/summary', [SupportController::class, 'summaryAdmin'])->middleware('permission:support.handle_reports');
        Route::get('/cases', [SupportController::class, 'queue'])->middleware('permission:support.handle_reports');
        Route::get('/cases/{case}', [SupportController::class, 'showAdmin'])->middleware('permission:support.handle_reports');
        Route::post('/cases/{case}/start', [SupportController::class, 'start'])->middleware('permission:support.handle_reports');
        Route::post('/cases/{case}/reply', [SupportController::class, 'replyAdmin'])->middleware('permission:support.handle_reports');
        Route::post('/cases/{case}/note', [SupportController::class, 'note'])->middleware('permission:support.handle_reports');
        Route::patch('/cases/{case}/status', [SupportController::class, 'updateStatus'])->middleware('permission:support.handle_reports');
        Route::put('/cases/{case}/assign', [SupportController::class, 'assign'])->middleware('permission:support.reassign');
        Route::post('/cases/{case}/escalate', [SupportController::class, 'escalate'])->middleware('permission:support.escalate');
        Route::post('/cases/{case}/reopen', [SupportController::class, 'reopen'])->middleware('permission:support.reopen');
        Route::get('/agents', [SupportController::class, 'agents'])->middleware('permission:support.reassign');
        Route::get('/users/{user}', [SupportController::class, 'userContext'])->middleware(['permission:support.handle_reports','permission:users.view']);
        Route::get('/worklog', [SupportController::class, 'worklog'])->middleware('permission:support.view_worklog');
        Route::post('/escalate-overdue', [SupportController::class, 'escalateOverdue'])->middleware('permission:support.manage');
    });

    Route::prefix('admin/listing-review')->group(function () {
        Route::get('/queue', [ListingReviewController::class, 'queue'])->middleware('permission:listings.moderate');
        Route::get('/listings/{property}', [ListingReviewController::class, 'show'])->middleware('permission:listings.moderate');
        Route::post('/listings/{property}/start', [ListingReviewController::class, 'start'])->middleware('permission:listings.moderate');
        Route::post('/listings/{property}/return', [ListingReviewController::class, 'returnForCorrection'])->middleware('permission:listings.moderate');
        Route::post('/listings/{property}/approve', [ListingReviewController::class, 'approve'])->middleware('permission:listings.moderate');
        Route::post('/listings/{property}/reject-final', [ListingReviewController::class, 'rejectFinal'])->middleware('permission:listings.moderate');
        Route::post('/listings/{property}/link-property', [ListingReviewController::class, 'linkPropertyAsset'])->middleware('permission:listings.moderate');
        Route::get('/blocks', [ListingReviewController::class, 'blocks'])->middleware('permission:listings.moderate');
        Route::post('/blocks/{block}/lift', [ListingReviewController::class, 'liftBlock'])->middleware('permission:listings.manage_blocks');
    });

    Route::prefix('admin/regions')->group(function () {
        Route::get('/governorates', [RegionsController::class, 'governorates'])->middleware('permission:regions.manage');
        Route::post('/governorates', [RegionsController::class, 'storeGovernorate'])->middleware('permission:regions.manage');
        Route::patch('/governorates/{governorate}', [RegionsController::class, 'updateGovernorate'])->middleware('permission:regions.manage');
        Route::get('/cells', [RegionsController::class, 'cells'])->middleware('permission:regions.manage');
        Route::get('/cells/{cell}/properties', [RegionsController::class, 'cellProperties'])->middleware('permission:regions.manage');
        Route::post('/cells', [RegionsController::class, 'storeCell'])->middleware('permission:regions.manage');
        Route::patch('/cells/{cell}', [RegionsController::class, 'updateCell'])->middleware('permission:regions.manage');
    });

    Route::prefix('admin/access')->group(function () {
        Route::get('/catalog', [AccessControlController::class, 'catalog'])->middleware('permission:users.view');
        Route::get('/users', [AccessControlController::class, 'users'])->middleware('permission:users.view');
        Route::patch('/users/{user}/status', [AccessControlController::class, 'updateStatus'])->middleware('permission:users.manage_status');
        Route::put('/users/{user}/roles', [AccessControlController::class, 'updateRoles'])->middleware('permission:users.manage_roles');
        Route::put('/users/{user}/permission-overrides', [AccessControlController::class, 'updatePermissionOverrides'])->middleware('permission:users.manage_permissions');
        Route::get('/audit-logs', [AccessControlController::class, 'auditLogs'])->middleware('permission:audit.view');
    });
});
