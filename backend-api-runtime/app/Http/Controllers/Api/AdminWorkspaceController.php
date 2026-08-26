<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PlatformSetting;
use App\Models\Property;
use App\Models\ServiceOrder;
use App\Models\SupportCase;
use App\Models\User;
use App\Models\ViewingBooking;
use App\Services\AuditLogService;
use App\Services\PlatformSettingsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class AdminWorkspaceController extends Controller
{
    public function __construct(private readonly PlatformSettingsService $settings, private readonly AuditLogService $audit) {}

    public function dashboard(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $alerts=[];
        $canUsers=$actor->hasPermission('users.view');
        $canListings=$actor->hasPermission('listings.moderate');
        $canSupport=$actor->hasPermission('support.handle_reports');
        $canBookings=$actor->hasPermission('bookings.manage');
        $canKyc=$actor->hasPermission('brokers.verify_accounts');
        $canPayments=$actor->hasPermission('payments.manage');

        $pendingListings=$canListings?Property::query()->whereIn('review_status',['submitted','under_review'])->count():0;
        $reviewWarningHours=(int)$this->settings->get('listings.review_warning_hours',24);
        $overdueListings=$canListings?Property::query()->whereIn('review_status',['submitted','under_review'])->where('submitted_at','<=',now()->subHours($reviewWarningHours))->count():0;
        $publishedListings=$canListings?Property::query()->where('status','published')->count():0;
        $openSupport=$canSupport?SupportCase::query()->whereIn('status',['open','in_progress','waiting_requester'])->count():0;
        $openReports=$canSupport?SupportCase::query()->where('kind','report')->whereIn('status',['open','in_progress','waiting_requester'])->count():0;
        $requestedBookings=$canBookings?ViewingBooking::query()->where('status','requested')->count():0;
        $activeBookings=$canBookings?ViewingBooking::query()->whereIn('status',['requested','confirmed'])->count():0;
        $pendingKyc=$canKyc?User::query()->where('account_type','broker')->where('broker_verification_status','pending')->count():0;
        $pendingPayments=$canPayments?ServiceOrder::query()->where('status','pending')->count():0;
        $overdue=$canSupport?SupportCase::query()->whereIn('status',['open','in_progress'])->where('sla_due_at','<=',now())->count():0;
        $showAlerts=(bool)$this->settings->get('notifications.dashboard_alerts_enabled',true);
        if($showAlerts){
            if($actor->hasPermission('listings.moderate') && $overdueListings>0) $alerts[]=['key'=>'listing_review','label'=>'إعلانات تجاوزت مدة المراجعة','count'=>$overdueListings,'route'=>'/admin/listing-review'];
            if($actor->hasPermission('support.handle_reports') && $overdue>0) $alerts[]=['key'=>'support_overdue','label'=>'حالات دعم متأخرة','count'=>$overdue,'route'=>'/support/workspace'];
            if($actor->hasPermission('brokers.verify_accounts') && $pendingKyc>0) $alerts[]=['key'=>'broker_kyc','label'=>'طلبات توثيق دلالين','count'=>$pendingKyc,'route'=>'/admin/broker-account-verifications'];
            if($actor->hasPermission('bookings.manage') && $requestedBookings>0) $alerts[]=['key'=>'bookings','label'=>'طلبات معاينة تنتظر الإجراء','count'=>$requestedBookings,'route'=>'/bookings'];
            if($actor->hasPermission('payments.manage') && $pendingPayments>0) $alerts[]=['key'=>'payments','label'=>'طلبات دفع معلقة','count'=>$pendingPayments,'route'=>'/services'];
        }
        return response()->json(['data'=>[
            'users'=>['total'=>$canUsers?User::query()->where('email','<>','stage5-owner@local.invalid')->count():0,'active'=>$canUsers?User::query()->where('account_status','active')->whereNotNull('phone_verified_at')->count():0],
            'listings'=>['pending_review'=>$pendingListings,'published'=>$publishedListings],
            'support'=>['open'=>$openSupport,'reports_open'=>$openReports,'overdue'=>$overdue],
            'bookings'=>['requested'=>$requestedBookings,'active'=>$activeBookings],
            'broker_kyc_pending'=>$pendingKyc,
            'payments_pending'=>$pendingPayments,
            'alerts'=>$alerts,
        ]]);
    }

    public function settings(Request $request): JsonResponse
    {
        return response()->json(['data'=>$this->settings->safeRows()]);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$request->validate([
            'settings'=>['required','array','min:1','max:20'],
            'settings.*.key'=>['required','string',Rule::in(PlatformSettingsService::SAFE_KEYS),'distinct'],
            'settings.*.value'=>['nullable'],
        ]);
        $before=[];$after=[];
        DB::transaction(function()use($v,$actor,&$before,&$after):void{
            foreach($v['settings'] as $item){
                $row=PlatformSetting::query()->where('key',$item['key'])->lockForUpdate()->firstOrFail();
                $before[$row->key]=$this->settings->typed($row->value,$row->value_type,null);
                $value=$this->normalize($row->key,$row->value_type,$item['value']);
                $row->forceFill(['value'=>$value,'updated_by_user_id'=>$actor->id])->save();
                $after[$row->key]=$this->settings->typed($value,$row->value_type,null);
            }
        });
        $this->audit->record($actor,'platform.settings_updated',null,['keys'=>array_keys($after),'before'=>$before,'after'=>$after],$request,$actor->id);
        return response()->json(['message'=>'Platform settings updated.','data'=>$this->settings->safeRows()]);
    }

    private function normalize(string $key,string $type,mixed $value): string
    {
        if($type==='boolean') return filter_var($value,FILTER_VALIDATE_BOOLEAN)?'true':'false';
        if($type==='integer'){
            $number=(int)$value;
            $min=1;$max=in_array($key,['support.sla_warning_hours','listings.review_warning_hours'],true)?168:336;
            abort_if($number<$min||$number>$max,422,'Invalid numeric setting value.');
            return (string)$number;
        }
        $text=trim((string)($value??''));
        abort_if(strlen($text)>250,422,'Setting value is too long.');
        if($key==='platform.contact_email' && $text!=='' && !filter_var($text,FILTER_VALIDATE_EMAIL)) abort(422,'Invalid contact email.');
        return $text;
    }
}
