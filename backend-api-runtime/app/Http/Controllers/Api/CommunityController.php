<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdvertiserRating;
use App\Models\ListingComment;
use App\Models\Property;
use App\Models\User;
use App\Services\ApiTokenService;
use App\Services\AuditLogService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CommunityController extends Controller
{
    public function __construct(
        private readonly ApiTokenService $tokens,
        private readonly AuditLogService $audit,
    ) {}

    public function comments(Request $request, Property $property): JsonResponse
    {
        abort_unless($property->status === 'published',404);
        $viewer=$this->tokens->authenticate($request,false);
        $rows=ListingComment::query()->where('property_id',$property->id)->where('status','visible')->latest('id')->limit(100)->get();
        return response()->json(['data'=>$rows->map(fn(ListingComment $comment)=>$this->commentData($comment,$viewer))->values()]);
    }

    public function storeComment(Request $request, Property $property): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless($property->status === 'published',404);
        $validated=$request->validate(['body'=>['required','string','min:2','max:1500']]);
        $comment=ListingComment::query()->create([
            'property_id'=>$property->id,'author_user_id'=>$user->id,'author_name_snapshot'=>$user->name,
            'body'=>trim($validated['body']),'status'=>'visible',
        ]);
        $this->audit->record($user,'community.comment_created',$comment,['property_id'=>$property->id],$request,$user->id);
        return response()->json(['message'=>'Comment added.','data'=>$this->commentData($comment,$user)],201);
    }

    public function updateComment(Request $request, ListingComment $comment): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$comment->author_user_id===(int)$user->id,403);
        abort_if($comment->status==='deleted',409,'Deleted comments cannot be edited.');
        $validated=$request->validate(['body'=>['required','string','min:2','max:1500']]);
        $comment->forceFill(['body'=>trim($validated['body']),'edited_at'=>now()])->save();
        $this->audit->record($user,'community.comment_edited',$comment,[],$request,$user->id);
        return response()->json(['message'=>'Comment updated.','data'=>$this->commentData($comment->fresh(),$user)]);
    }

    public function deleteComment(Request $request, ListingComment $comment): JsonResponse
    {
        /** @var User $user */ $user=$request->user();
        abort_unless((int)$comment->author_user_id===(int)$user->id,403);
        if($comment->status!=='deleted'){
            $comment->forceFill(['status'=>'deleted','edited_at'=>now()])->save();
            $this->audit->record($user,'community.comment_deleted',$comment,[],$request,$user->id);
        }
        return response()->json(['message'=>'Comment removed.']);
    }

    public function hideComment(Request $request, ListingComment $comment): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['reason'=>['required','string','min:5','max:500']]);
        abort_if($comment->status==='deleted',409,'Deleted comments cannot be moderated.');
        $comment->forceFill([
            'status'=>'hidden','moderated_by_user_id'=>$actor->id,'moderated_by_name_snapshot'=>$actor->name,
            'moderation_reason'=>trim($validated['reason']),'moderated_at'=>now(),
        ])->save();
        $this->audit->record($actor,'community.comment_hidden',$comment,['reason'=>$validated['reason']],$request,$comment->author_user_id);
        return response()->json(['message'=>'Comment hidden.','data'=>$this->commentData($comment->fresh(),$actor,true)]);
    }

    public function unhideComment(Request $request, ListingComment $comment): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_unless($comment->status==='hidden',409);
        $comment->forceFill([
            'status'=>'visible','moderated_by_user_id'=>$actor->id,'moderated_by_name_snapshot'=>$actor->name,
            'moderation_reason'=>null,'moderated_at'=>now(),
        ])->save();
        $this->audit->record($actor,'community.comment_unhidden',$comment,[],$request,$comment->author_user_id);
        return response()->json(['message'=>'Comment restored.','data'=>$this->commentData($comment->fresh(),$actor,true)]);
    }

    public function ratingSummary(Request $request, User $advertiser): JsonResponse
    {
        $viewer=$this->tokens->authenticate($request,false);
        return response()->json(['data'=>$this->ratingSummaryData($advertiser,$viewer)]);
    }

    public function upsertRating(Request $request, User $advertiser): JsonResponse
    {
        /** @var User $rater */ $rater=$request->user();
        if((int)$rater->id===(int)$advertiser->id) throw ValidationException::withMessages(['advertiser'=>['You cannot rate your own advertiser account.']]);
        $validated=$request->validate([
            'rating'=>['required','integer','between:1,5'],
            'comment'=>['nullable','string','max:1000'],
            'property_id'=>['nullable','integer','exists:properties,id'],
        ]);
        $published=Property::query()->where('user_id',$advertiser->id)->where('status','published');
        if(isset($validated['property_id'])) $published->whereKey((int)$validated['property_id']);
        if(!$published->exists()) throw ValidationException::withMessages(['advertiser'=>['Advertiser must have a published listing.']]);

        $existing=AdvertiserRating::query()->where('advertiser_user_id',$advertiser->id)->where('rater_user_id',$rater->id)->first();
        if($existing){
            $existing->forceFill([
                'rating'=>(int)$validated['rating'],'comment'=>isset($validated['comment'])?trim((string)$validated['comment']):null,
                'source_property_id'=>$validated['property_id']??$existing->source_property_id,
                'advertiser_name_snapshot'=>$advertiser->name,'rater_name_snapshot'=>$rater->name,
            ])->save();$rating=$existing->fresh();$created=false;
        }else{
            $rating=AdvertiserRating::query()->create([
                'advertiser_user_id'=>$advertiser->id,'advertiser_name_snapshot'=>$advertiser->name,
                'rater_user_id'=>$rater->id,'rater_name_snapshot'=>$rater->name,
                'source_property_id'=>$validated['property_id']??null,'rating'=>(int)$validated['rating'],
                'comment'=>isset($validated['comment'])?trim((string)$validated['comment']):null,'status'=>'visible',
            ]);$created=true;
        }
        $this->audit->record($rater,$created?'community.rating_created':'community.rating_updated',$rating,['advertiser_user_id'=>$advertiser->id,'rating'=>$rating->rating],$request,$advertiser->id);
        return response()->json(['message'=>$created?'Rating added.':'Rating updated.','data'=>$this->ratingSummaryData($advertiser,$rater)],$created?201:200);
    }

    public function deleteRating(Request $request, User $advertiser): JsonResponse
    {
        /** @var User $rater */ $rater=$request->user();
        $rating=AdvertiserRating::query()->where('advertiser_user_id',$advertiser->id)->where('rater_user_id',$rater->id)->firstOrFail();
        $id=$rating->id;$rating->delete();
        $this->audit->record($rater,'community.rating_deleted',null,['rating_id'=>$id,'advertiser_user_id'=>$advertiser->id],$request,$advertiser->id);
        return response()->json(['message'=>'Rating removed.']);
    }

    public function hideRating(Request $request, AdvertiserRating $rating): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $validated=$request->validate(['reason'=>['required','string','min:5','max:500']]);
        $rating->forceFill([
            'status'=>'hidden','moderated_by_user_id'=>$actor->id,'moderated_by_name_snapshot'=>$actor->name,
            'moderation_reason'=>trim($validated['reason']),'moderated_at'=>now(),
        ])->save();
        $this->audit->record($actor,'community.rating_hidden',$rating,['reason'=>$validated['reason']],$request,$rating->rater_user_id);
        return response()->json(['message'=>'Rating hidden.']);
    }

    public function unhideRating(Request $request, AdvertiserRating $rating): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_unless($rating->status==='hidden',409);
        $rating->forceFill(['status'=>'visible','moderated_by_user_id'=>$actor->id,'moderated_by_name_snapshot'=>$actor->name,'moderation_reason'=>null,'moderated_at'=>now()])->save();
        $this->audit->record($actor,'community.rating_unhidden',$rating,[],$request,$rating->rater_user_id);
        return response()->json(['message'=>'Rating restored.']);
    }

    private function commentData(ListingComment $comment, ?User $viewer, bool $includeModeration=false): array
    {
        $data=[
            'id'=>$comment->id,'property_id'=>$comment->property_id,'author_user_id'=>$comment->author_user_id,
            'author_name'=>$comment->author_name_snapshot,'body'=>$comment->body,'status'=>$comment->status,
            'edited_at'=>$comment->edited_at?->toIso8601String(),'created_at'=>$comment->created_at?->toIso8601String(),
            'is_owner'=>$viewer!==null&&(int)$viewer->id===(int)$comment->author_user_id,
        ];
        if($includeModeration){$data['moderation_reason']=$comment->moderation_reason;$data['moderated_at']=$comment->moderated_at?->toIso8601String();}
        return $data;
    }

    private function ratingSummaryData(User $advertiser, ?User $viewer): array
    {
        $base=AdvertiserRating::query()->where('advertiser_user_id',$advertiser->id)->where('status','visible');
        $count=(clone $base)->count();$average=$count>0?round((float)(clone $base)->avg('rating'),2):0.0;
        $distribution=[];for($score=1;$score<=5;$score++)$distribution[(string)$score]=(clone $base)->where('rating',$score)->count();
        $mine=$viewer?AdvertiserRating::query()->where('advertiser_user_id',$advertiser->id)->where('rater_user_id',$viewer->id)->first():null;
        return [
            'advertiser_id'=>$advertiser->id,'advertiser_name'=>$advertiser->name,'average'=>$average,'count'=>$count,
            'distribution'=>$distribution,
            'my_rating'=>$mine?['id'=>$mine->id,'rating'=>(int)$mine->rating,'comment'=>$mine->comment,'status'=>$mine->status]:null,
        ];
    }
}
