<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PropertyPlatformReceivable extends Model
{
    public const SUPPORT_RESTORE_REASON = 'support_restored_platform_receivable';

    protected $fillable = [
        'reference','deal_financial_term_id','property_id','advertiser_user_id','amount_total','amount_paid',
        'currency','status','confirmed_direct_at','due_at','paid_at',
    ];

    protected function casts(): array
    {
        return [
            'amount_total'=>'float','amount_paid'=>'float','confirmed_direct_at'=>'datetime','due_at'=>'datetime','paid_at'=>'datetime',
        ];
    }

    public function advertiser(): BelongsTo { return $this->belongsTo(User::class, 'advertiser_user_id'); }
    public function financialTerm(): BelongsTo { return $this->belongsTo(PropertyDealFinancialTerm::class, 'deal_financial_term_id'); }

    public function scopeOutstanding(Builder $query): Builder
    {
        return $query->whereIn('status', ['open', 'under_review', 'overdue', 'disputed'])
            ->whereColumn('amount_paid', '<', 'amount_total');
    }

    public function scopeRestrictsListings(Builder $query): Builder
    {
        return $query->outstanding()->whereNotExists(function ($release): void {
            $release->selectRaw('1')->from('property_financial_holds')
                ->whereColumn('user_id', 'property_platform_receivables.advertiser_user_id')
                ->whereColumn('source_id', 'property_platform_receivables.id')
                ->where('source_type', 'property_platform_receivable')
                ->where('release_reason', self::SUPPORT_RESTORE_REASON)
                ->whereNotNull('released_at');
        });
    }

    public function scopeOverdueListingRestriction(Builder $query): Builder
    {
        return $query->restrictsListings()->where('due_at', '<=', now());
    }
}
