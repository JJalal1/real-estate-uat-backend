<?php

namespace App\Models;

use App\Services\PropertySaiSettlementService;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertyAgreement extends Model
{
    protected $fillable = [
        'reference','property_id','message_thread_id','viewing_booking_id','requester_user_id','advertiser_user_id',
        'transaction_type','status','created_by_user_id','accepted_at','cancelled_at','cancellation_reason',
    ];

    protected static function booted(): void
    {
        static::creating(function (PropertyAgreement $agreement): void {
            if (! $agreement->message_thread_id || ! $agreement->property_id) {
                return;
            }

            $thread = MessageThread::query()
                ->whereKey($agreement->message_thread_id)
                ->lockForUpdate()
                ->first();
            if (! $thread) {
                return;
            }

            if ((int) $thread->property_id !== (int) $agreement->property_id) {
                abort(409, 'Agreement property does not match its conversation.');
            }

            // New conversations already snapshot Sai when the thread is
            // created. For a legacy thread, freeze the current listing term at
            // the moment the transaction journey actually starts.
            if ($thread->sai_term_id === null) {
                $termId = Property::query()
                    ->whereKey($agreement->property_id)
                    ->value('current_sai_term_id');
                if ($termId !== null) {
                    $thread->forceFill(['sai_term_id' => $termId])->save();
                }
            }
        });

        static::updated(function (PropertyAgreement $agreement): void {
            if ($agreement->wasChanged('status') && $agreement->status === 'accepted') {
                app(PropertySaiSettlementService::class)->settleAcceptedAgreement($agreement);
            }
        });
    }

    protected function casts(): array
    {
        return [
            'property_id'=>'integer','message_thread_id'=>'integer','viewing_booking_id'=>'integer',
            'requester_user_id'=>'integer','advertiser_user_id'=>'integer','created_by_user_id'=>'integer',
            'accepted_at'=>'datetime','cancelled_at'=>'datetime',
        ];
    }

    public function property(): BelongsTo { return $this->belongsTo(Property::class); }
    public function thread(): BelongsTo { return $this->belongsTo(MessageThread::class, 'message_thread_id'); }
    public function viewing(): BelongsTo { return $this->belongsTo(ViewingBooking::class, 'viewing_booking_id'); }
}
