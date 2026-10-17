<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ListingEditorDraft;
use App\Models\Property;
use App\Models\User;
use App\Services\CloudAssetStorageService;
use App\Services\ListingAccessService;
use App\Services\ListingEditorDraftService;
use App\Services\PropertyIdentityService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ListingEditorDraftController extends Controller
{
    public function __construct(private readonly ListingEditorDraftService $drafts) {}

    public function index(Request $request)
    {
        $rows=ListingEditorDraft::query()->where('user_id',$request->user()->id)
            ->where(function($q):void {$q->whereNull('property_id')->orWhereHas('property',fn($p)=>$p->where('status','draft')->whereNotIn('review_status',['submitted','under_review','rejected_blocked']));})
            ->orderByDesc('updated_at')->orderByDesc('id')->paginate(50);
        return response()->json(['data'=>$rows->getCollection()->map(fn($d)=>$this->drafts->present($d)),
            'meta'=>['current_page'=>$rows->currentPage(),'last_page'=>$rows->lastPage()]]);
    }
    public function show(Request $request,string $key) { return response()->json(['data'=>$this->drafts->present($this->drafts->owned($request->user(),$key))]); }

    public function save(Request $request,string $key)
    {
        abort_unless(Str::isUuid($key),404);
        $v=$request->validate(['payload'=>['required','array'],'expected_revision'=>['required','integer','min:0'],'property_id'=>['nullable','integer','min:1']]);
        abort_if(strlen(json_encode($v['payload']))>100000,422);
        $result=DB::transaction(function()use($request,$key,$v){
            $actor=User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $property=isset($v['property_id'])?Property::query()->findOrFail($v['property_id']):null;
            $this->drafts->assertEditable($actor,$property);
            $draft=ListingEditorDraft::query()->where('user_id',$actor->id)->where('client_key',$key)->lockForUpdate()->first();
            if (!$draft) {
                abort_unless($v['expected_revision']===0,409);
                if (!$property) app(ListingAccessService::class)->assertCanCreate($actor,$key);
                $draft=new ListingEditorDraft(['user_id'=>$actor->id,'client_key'=>$key,'revision'=>0,'images'=>[],'payload'=>[],'property_id'=>$property?->id]);
            } else {
                $this->drafts->assertRevision($draft,$v['expected_revision']);
                if ($draft->property_id) $this->drafts->assertEditable($actor,Property::query()->findOrFail($draft->property_id));
                abort_if($property && $draft->property_id !== null && (int)$property->id !== $draft->property_id,409);
            }
            $draft->payload=$this->drafts->clean($v['payload']);
            if ($property) $draft->property_id=$property->id;
            $draft->revision++;$draft->save();return $draft;
        });
        return response()->json(['data'=>$this->drafts->present($result)]);
    }

    public function upload(Request $request,string $key,string $imageKey,CloudAssetStorageService $storage)
    {
        abort_unless(Str::isUuid($imageKey),404);
        $request->validate(['image'=>['required','file','image','mimes:jpg,jpeg,png,webp','max:8192'],'expected_revision'=>['required','integer','min:0']]);
        $path=null;
        try {$result=DB::transaction(function()use($request,$key,$imageKey,$storage,&$path){
            User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $draft=$this->drafts->owned($request->user(),$key,true);
            $this->drafts->assertEditable($request->user(),$draft->property_id?Property::query()->findOrFail($draft->property_id):null);
            $images=$draft->images;if(isset($images[$imageKey]))return $draft;
            $this->drafts->assertRevision($draft,$request->integer('expected_revision'));
            abort_if(count($images)>=12,422);
            $path=$storage->storePrivate($request->file('image'),'editor-drafts/'.$request->user()->id.'/'.$key);
            $images[$imageKey]=$path;$draft->images=$images;$draft->revision++;$draft->save();return $draft;
        });}catch(\Throwable $e){if($path)$storage->deletePrivate($path);throw $e;}
        return response()->json(['data'=>$this->drafts->present($result)]);
    }

    public function image(Request $request,string $key,string $imageKey,CloudAssetStorageService $storage)
    {
        $draft=$this->drafts->owned($request->user(),$key);$path=$draft->images[$imageKey] ?? null;abort_unless($path,404);
        return $storage->responsePrivate($path,null,['Cache-Control'=>'private, no-store']);
    }

    public function removeImage(Request $request,string $key,string $imageKey)
    {
        $request->validate(['expected_revision'=>['required','integer','min:0']]);$path=null;
        $result=DB::transaction(function()use($request,$key,$imageKey,&$path){
            User::query()->lockForUpdate()->findOrFail($request->user()->id);$draft=$this->drafts->owned($request->user(),$key,true);
            $this->drafts->assertEditable($request->user(),$draft->property_id?Property::query()->findOrFail($draft->property_id):null);
            $this->drafts->assertRevision($draft,$request->integer('expected_revision'));
            $images=$draft->images;$path=$images[$imageKey]??null;unset($images[$imageKey]);$draft->images=$images;$draft->revision++;$draft->save();return $draft;
        });
        if($path)$this->drafts->removeFiles([$path]);return response()->json(['data'=>$this->drafts->present($result)]);
    }

    public function destroy(Request $request,string $key)
    {
        $paths=DB::transaction(function()use($request,$key){
            User::query()->lockForUpdate()->findOrFail($request->user()->id);$draft=$this->drafts->owned($request->user(),$key,true);
            if($draft->property_id){$property=Property::query()->lockForUpdate()->find($draft->property_id);
                if($property && $property->status==='draft'){$this->drafts->assertEditable($request->user(),$property);
                    app(PropertyIdentityService::class)->releaseRepresentationForListing($property,'editor_draft_deleted');$property->status='archived';$property->save();}}
            $paths=array_values($draft->images);$draft->delete();return $paths;
        });
        $this->drafts->removeFiles($paths);return response()->json(['message'=>'حذفت المسودة.']);
    }
}
