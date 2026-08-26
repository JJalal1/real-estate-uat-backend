<?php
namespace App\Services;

use App\Models\BrokerCellAssignment;
use App\Models\ListingBrokerVerification;
use App\Models\Property;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class BrokerListingVerificationService
{
    public function __construct(
        private readonly AuditLogService $audit,
        private readonly RegionService $regions,
        private readonly UserNotificationService $notifications,
    ) {}

    public function statusFor(Property $listing): array
    {
        // UAT account/KYC policy: broker territory ownership and the old
        // main/sub-broker availability confirmation workflow are retired.
        // Historical rows remain readable for audit, but they never gate
        // support approval and no new request is required.
        return [
            'required'=>false,
            'approval_allowed'=>true,
            'reason'=>'broker_region_verification_retired',
            'geo_cell_id'=>$listing->geo_cell_id,
            'geo_cell_name'=>null,
            'broker'=>null,
            'latest'=>null,
        ];
    }

    public function request(User $actor, Property $listing, ?string $note, Request $request): ListingBrokerVerification
    {
        if (! in_array($listing->review_status,['submitted','under_review'],true)) {
            throw new ConflictHttpException('Listing is not awaiting review.');
        }
        $state=$this->statusFor($listing);
        if (! $state['required']) {
            throw new ConflictHttpException('Official broker verification is not required for this listing.');
        }
        $cellId=(int)$state['geo_cell_id'];
        $brokerId=(int)$state['broker']['id'];
        $broker=User::query()->findOrFail($brokerId);

        return DB::transaction(function() use($actor,$listing,$note,$request,$cellId,$brokerId,$broker){
            $this->cancelStalePending($listing,$cellId,$brokerId);
            $duplicate=ListingBrokerVerification::query()
                ->where('listing_id',$listing->id)->where('status','pending')->lockForUpdate()->first();
            if($duplicate){throw new ConflictHttpException('A broker verification request is already pending for this listing.');}
            $verification=ListingBrokerVerification::query()->create([
                'listing_id'=>$listing->id,
                'geo_cell_id'=>$cellId,
                'broker_user_id'=>$brokerId,
                'requested_by_user_id'=>$actor->id,
                'requested_by_name_snapshot'=>$actor->name,
                'broker_name_snapshot'=>$broker->name,
                'status'=>'pending',
                'request_note'=>$note,
                'requested_at'=>now(),
            ]);
            $this->notifications->create(
                $brokerId,
                'listing_broker_verification_requested',
                'طلب تحقق من حالة عقار',
                'طلب منك الدعم التحقق من حالة عقار داخل مربعك قبل اعتماد الإعلان.',
                'listing_broker_verification',$verification->id,
                ['listing_id'=>$listing->id,'geo_cell_id'=>$cellId],
            );
            $this->audit->record($actor,'listing.broker_verification_requested',$verification,[
                'listing_id'=>$listing->id,'geo_cell_id'=>$cellId,'broker_user_id'=>$brokerId,
            ],$request,$listing->user_id);
            return $verification->fresh(['listing','broker','geoCell']);
        });
    }

    public function respond(User $actor, ListingBrokerVerification $verification, string $status, ?string $note, Request $request): ListingBrokerVerification
    {
        if (! in_array($status,['available','unavailable','unable_to_verify'],true)) {
            throw new ConflictHttpException('Invalid broker verification response status.');
        }
        $stale=false;
        $result=DB::transaction(function() use($actor,$verification,$status,$note,$request,&$stale){
            $row=ListingBrokerVerification::query()->whereKey($verification->id)->lockForUpdate()->firstOrFail();
            if((int)$row->broker_user_id !== (int)$actor->id){throw new AccessDeniedHttpException('You are not the assigned broker for this verification.');}
            if($row->status !== 'pending'){throw new ConflictHttpException('This broker verification request is already closed.');}
            $current=BrokerCellAssignment::query()->where('geo_cell_id',$row->geo_cell_id)->whereNull('ends_at')->first();
            if(!$current || (int)$current->broker_user_id !== (int)$actor->id){
                $row->forceFill(['status'=>'cancelled','cancelled_at'=>now(),'cancel_reason'=>'Official broker assignment changed before response.'])->save();
                $stale=true;
                return $row->fresh();
            }
            $row->forceFill(['status'=>$status,'response_note'=>$note,'responded_at'=>now()])->save();
            if($row->requested_by_user_id){
                $this->notifications->create(
                    (int)$row->requested_by_user_id,
                    'listing_broker_verification_responded',
                    'تم الرد على طلب تحقق العقار',
                    match($status){'available'=>'أكد الدلال أن العقار متاح.','unavailable'=>'أفاد الدلال أن العقار غير متاح.','unable_to_verify'=>'أفاد الدلال أنه لا يستطيع التأكد من حالة العقار.'},
                    'listing_broker_verification',$row->id,
                    ['listing_id'=>$row->listing_id,'status'=>$status],
                );
            }
            $this->audit->record($actor,'listing.broker_verification_responded',$row,[
                'listing_id'=>$row->listing_id,'geo_cell_id'=>$row->geo_cell_id,'status'=>$status,
            ],$request,$row->listing?->user_id);
            return $row->fresh(['listing','broker','geoCell']);
        });
        if($stale){throw new ConflictHttpException('The official broker assignment changed. Ask support to create a new verification request.');}
        return $result;
    }

    public function assertApprovalAllowed(Property $listing): void
    {
        $state=$this->statusFor($listing);
        if(! $state['required']) return;
        $latest=$state['latest'];
        if(!$latest){throw new ConflictHttpException('Official broker verification is required before approval.');}
        if(($latest['status']??null)==='pending'){throw new ConflictHttpException('Official broker verification is still pending.');}
        if(($latest['status']??null)!=='available'){
            throw new ConflictHttpException('The official broker has not confirmed that the property is available.');
        }
    }

    public function brokerQueue(User $actor, ?string $status='pending'): array
    {
        $q=ListingBrokerVerification::query()->with(['listing','geoCell'])
            ->where('broker_user_id',$actor->id);
        if($status){$q->where('status',$status);}
        return $q->latest('id')->limit(100)->get()->map(fn(ListingBrokerVerification $v)=>$this->brokerData($v))->all();
    }

    public function verificationData(ListingBrokerVerification $v): array
    {
        return [
            'id'=>$v->id,'status'=>$v->status,'request_note'=>$v->request_note,'response_note'=>$v->response_note,
            'requested_at'=>$v->requested_at?->toIso8601String(),'responded_at'=>$v->responded_at?->toIso8601String(),
            'cancelled_at'=>$v->cancelled_at?->toIso8601String(),'cancel_reason'=>$v->cancel_reason,
            'broker_user_id'=>$v->broker_user_id,'broker_name'=>$v->broker_name_snapshot,
            'requested_by_name'=>$v->requested_by_name_snapshot,'geo_cell_id'=>$v->geo_cell_id,
        ];
    }

    private function brokerData(ListingBrokerVerification $v): array
    {
        $listing=$v->listing;
        return $this->verificationData($v)+[
            'listing'=>[
                'id'=>$listing?->id,'title'=>$listing?->title,'purpose'=>$listing?->purpose,'type'=>$listing?->type,
                'address'=>$listing?->address,'area_value'=>$listing?->area_value,'area_unit'=>$listing?->area_unit,
                'area_m2'=>$listing?->area_m2,'review_status'=>$listing?->review_status,
            ],
            'geo_cell_name'=>$v->geoCell?->name_ar,
        ];
    }

    private function cancelStalePending(Property $listing, int $cellId, int $brokerId): void
    {
        ListingBrokerVerification::query()
            ->where('listing_id',$listing->id)->where('status','pending')
            ->where(function($q) use($cellId,$brokerId){$q->where('geo_cell_id','<>',$cellId)->orWhere('broker_user_id','<>',$brokerId);})
            ->update(['status'=>'cancelled','cancelled_at'=>now(),'cancel_reason'=>'Official broker assignment changed; a new verification request is required.','updated_at'=>now()]);
    }
}
