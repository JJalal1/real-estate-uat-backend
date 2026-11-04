<?php
namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;

/** Personal messaging preferences, never an account ban or a substitute permission model. */
class UserMessagingBlockService
{
    public function lockPair(int $first,int $second):void
    {
        $ids=[$first,$second];sort($ids);
        if (DB::getDriverName()==='pgsql') DB::select('SELECT pg_advisory_xact_lock(hashtext(?))',['messaging-block:'.implode(':',$ids)]);
    }
    public function blockedBy(int $first,int $second):bool
    {
        return DB::table('user_messaging_blocks')->where('user_id',$first)->where('blocked_user_id',$second)->exists();
    }
    public function statesFor(int $actor,array $others):array
    {
        $states=[];foreach($others as $id) $states[(int)$id]=['can_send'=>true,'blocked_by_me'=>false];
        $rows=DB::table('user_messaging_blocks')->where(fn($q)=>$q->where('user_id',$actor)->whereIn('blocked_user_id',$others))
            ->orWhere(fn($q)=>$q->where('blocked_user_id',$actor)->whereIn('user_id',$others))->get();
        foreach ($rows as $row) {
            $mine=(int)$row->user_id===$actor;$other=$mine?(int)$row->blocked_user_id:(int)$row->user_id;
            $states[$other]['can_send']=false;if($mine)$states[$other]['blocked_by_me']=true;
        }
        return $states;
    }
    public function canSend(int $first,int $second):bool { return $this->statesFor($first,[$second])[$second]['can_send']; }
    public function assertCanSend(int $first,int $second):void
    {
        $this->lockPair($first,$second);
        abort_unless($this->canSend($first,$second),403,'لا يمكن إرسال رسائل جديدة في هذه المحادثة حاليًا.');
    }
}
