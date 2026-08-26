<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Developer;
use App\Models\Development;
use App\Models\DevelopmentUnit;
use App\Models\User;
use App\Services\AuditLogService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class DevelopmentController extends Controller
{
    public function __construct(private readonly AuditLogService $audit) {}

    public function developers(Request $request): JsonResponse
    {
        $rows=Developer::query()->where('status','active')
            ->whereHas('developments',fn($q)=>$q->where('status','published'))
            ->withCount(['developments as published_projects_count'=>fn($q)=>$q->where('status','published')])
            ->orderBy('name')->get();
        return response()->json(['data'=>$rows->map(fn(Developer $d)=>$this->developerData($d))->values()]);
    }

    public function developerShow(Developer $developer): JsonResponse
    {
        abort_unless($developer->status==='active',404);
        $developer->load(['developments'=>fn($q)=>$q->where('status','published')->withCount(['units'=>fn($u)=>$u->where('status','<>','hidden'),'units as available_units_count'=>fn($u)=>$u->where('status','available')])->latest('published_at')]);
        if($developer->developments->isEmpty()) abort(404);
        return response()->json(['data'=>$this->developerData($developer,true)]);
    }

    public function index(Request $request): JsonResponse
    {
        $validated=$request->validate([
            'developer_id'=>['nullable','integer','exists:developers,id'],
            'governorate_id'=>['nullable','integer','exists:governorates,id'],
            'completion_status'=>['nullable',Rule::in(['planned','under_construction','completed'])],
            'unit_status'=>['nullable',Rule::in(['available','reserved','sold'])],
            'q'=>['nullable','string','max:120'],
        ]);
        $q=Development::query()->where('status','published')->whereHas('developer',fn($d)=>$d->where('status','active'))
            ->with(['developer:id,name,slug,status','governorate:id,name_ar,name_en','geoCell:id,code,name_ar,name_en'])
            ->withCount(['units'=>fn($u)=>$u->where('status','<>','hidden'),'units as available_units_count'=>fn($u)=>$u->where('status','available')])
            ->when($validated['developer_id']??null,fn($x,$v)=>$x->where('developer_id',$v))
            ->when($validated['governorate_id']??null,fn($x,$v)=>$x->where('governorate_id',$v))
            ->when($validated['completion_status']??null,fn($x,$v)=>$x->where('completion_status',$v))
            ->when($validated['unit_status']??null,fn($x,$v)=>$x->whereHas('units',fn($u)=>$u->where('status',$v)))
            ->when(trim((string)($validated['q']??''))!=='',function($x)use($validated){$term='%'.trim($validated['q']).'%';$x->where(function($inner)use($term){$inner->where('name','like',$term)->orWhere('description','like',$term)->orWhere('address','like',$term)->orWhereHas('developer',fn($d)=>$d->where('name','like',$term));});})
            ->latest('published_at')->limit(200)->get();
        return response()->json(['data'=>$q->map(fn(Development $d)=>$this->projectData($d,false))->values()]);
    }

    public function show(Development $development): JsonResponse
    {
        abort_unless($development->status==='published',404);
        $development->load(['developer','governorate:id,name_ar,name_en','geoCell:id,code,name_ar,name_en','units'=>fn($q)=>$q->where('status','<>','hidden')->orderBy('id')]);
        abort_unless($development->developer?->status==='active',404);
        return response()->json(['data'=>$this->projectData($development,true)]);
    }

    public function adminDevelopers(): JsonResponse
    {
        $rows=Developer::query()->withCount('developments')->orderBy('name')->get();
        return response()->json(['data'=>$rows->map(fn(Developer $d)=>$this->developerData($d))->values()]);
    }

    public function storeDeveloper(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$this->developerRules($request);
        $developer=Developer::query()->create($v+['created_by_user_id'=>$actor->id,'created_by_name_snapshot'=>$actor->name]);
        $this->audit->record($actor,'developments.developer_created',$developer,['slug'=>$developer->slug],$request);
        return response()->json(['message'=>'Developer created.','data'=>$this->developerData($developer)],201);
    }

    public function updateDeveloper(Request $request, Developer $developer): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$this->developerRules($request,$developer);
        $developer->fill($v)->save();
        $this->audit->record($actor,'developments.developer_updated',$developer,['status'=>$developer->status],$request);
        return response()->json(['message'=>'Developer updated.','data'=>$this->developerData($developer->fresh())]);
    }

    public function adminProjects(Request $request): JsonResponse
    {
        $v=$request->validate(['status'=>['nullable',Rule::in(['draft','published','archived'])],'developer_id'=>['nullable','integer','exists:developers,id']]);
        $rows=Development::query()->with(['developer:id,name,slug,status','governorate:id,name_ar,name_en','geoCell:id,code,name_ar,name_en'])
            ->withCount(['units','units as available_units_count'=>fn($u)=>$u->where('status','available')])
            ->when($v['status']??null,fn($q,$x)=>$q->where('status',$x))
            ->when($v['developer_id']??null,fn($q,$x)=>$q->where('developer_id',$x))
            ->latest('id')->limit(300)->get();
        return response()->json(['data'=>$rows->map(fn(Development $d)=>$this->projectData($d,false))->values()]);
    }

    public function adminProjectShow(Development $development): JsonResponse
    {
        $development->load(['developer','governorate:id,name_ar,name_en','geoCell:id,code,name_ar,name_en','units'=>fn($q)=>$q->orderBy('id')]);
        return response()->json(['data'=>$this->projectData($development,true)]);
    }

    public function storeProject(Request $request): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$this->projectRules($request);
        $v=$this->normalizeLocation($v);
        $project=Development::query()->create($v+['created_by_user_id'=>$actor->id,'created_by_name_snapshot'=>$actor->name,'status'=>'draft']);
        $this->audit->record($actor,'developments.project_created',$project,['developer_id'=>$project->developer_id,'slug'=>$project->slug],$request);
        $project->load(['developer','governorate','geoCell']);
        return response()->json(['message'=>'Development created as draft.','data'=>$this->projectData($project,false)],201);
    }

    public function updateProject(Request $request, Development $development): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_if($development->status==='archived',409,'Archived developments cannot be edited.');
        $v=$this->projectRules($request,$development);
        $v=$this->normalizeLocation($v,$development);
        $development->fill($v)->save();
        $this->audit->record($actor,'developments.project_updated',$development,['status'=>$development->status],$request);
        $development->load(['developer','governorate','geoCell']);
        return response()->json(['message'=>'Development updated.','data'=>$this->projectData($development,false)]);
    }

    public function publish(Request $request, Development $development): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_if($development->status==='archived',409,'Archived developments cannot be published.');
        $development->load('developer');
        if($development->developer?->status!=='active') throw ValidationException::withMessages(['developer_id'=>['The developer must be active before publication.']]);
        if(!$development->units()->where('status','<>','hidden')->exists()) throw ValidationException::withMessages(['units'=>['At least one visible unit is required before publication.']]);
        $development->forceFill(['status'=>'published','published_at'=>now(),'published_by_user_id'=>$actor->id,'published_by_name_snapshot'=>$actor->name])->save();
        $this->audit->record($actor,'developments.project_published',$development,['developer_id'=>$development->developer_id],$request);
        return response()->json(['message'=>'Development published.','data'=>$this->projectData($development->fresh()->load('developer'),false)]);
    }

    public function unpublish(Request $request, Development $development): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_unless($development->status==='published',409,'Only published developments can be unpublished.');
        $development->forceFill(['status'=>'draft','published_at'=>null,'published_by_user_id'=>null,'published_by_name_snapshot'=>null])->save();
        $this->audit->record($actor,'developments.project_unpublished',$development,[],$request);
        return response()->json(['message'=>'Development unpublished.','data'=>$this->projectData($development->fresh()->load('developer'),false)]);
    }

    public function storeUnit(Request $request, Development $development): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        abort_if($development->status==='archived',409,'Archived developments cannot receive units.');
        $v=$this->unitRules($request,$development);
        $unit=$development->units()->create($v);
        $this->audit->record($actor,'developments.unit_created',$unit,['development_id'=>$development->id,'code'=>$unit->code],$request);
        return response()->json(['message'=>'Unit created.','data'=>$this->unitData($unit)],201);
    }

    public function updateUnit(Request $request, DevelopmentUnit $unit): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        $v=$this->unitRules($request,$unit->development,$unit);
        $unit->fill($v)->save();
        $this->audit->record($actor,'developments.unit_updated',$unit,['development_id'=>$unit->development_id,'status'=>$unit->status],$request);
        return response()->json(['message'=>'Unit updated.','data'=>$this->unitData($unit->fresh())]);
    }

    public function deleteUnit(Request $request, DevelopmentUnit $unit): JsonResponse
    {
        /** @var User $actor */ $actor=$request->user();
        if(in_array($unit->status,['reserved','sold'],true)) abort(409,'Reserved or sold units cannot be deleted.');
        $id=$unit->id;$developmentId=$unit->development_id;$code=$unit->code;
        $unit->delete();
        $this->audit->record($actor,'developments.unit_deleted',null,['unit_id'=>$id,'development_id'=>$developmentId,'code'=>$code],$request);
        return response()->json(['message'=>'Unit deleted.']);
    }

    private function developerRules(Request $request, ?Developer $developer=null): array
    {
        return $request->validate([
            'name'=>['required','string','min:2','max:160'],
            'slug'=>['required','string','max:160','regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/',Rule::unique('developers','slug')->ignore($developer?->id)],
            'description'=>['nullable','string','max:10000'],
            'website'=>['nullable','url','max:500'],'phone'=>['nullable','string','max:40'],'email'=>['nullable','email','max:190'],'logo_url'=>['nullable','url','max:500'],
            'status'=>['required',Rule::in(['active','inactive'])],
        ]);
    }

    private function projectRules(Request $request, ?Development $development=null): array
    {
        return $request->validate([
            'developer_id'=>['required','integer','exists:developers,id'],
            'name'=>['required','string','min:2','max:180'],
            'slug'=>['required','string','max:180','regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/',Rule::unique('developments','slug')->ignore($development?->id)],
            'description'=>['nullable','string','max:20000'],
            'completion_status'=>['required',Rule::in(['planned','under_construction','completed'])],
            'expected_completion_date'=>['nullable','date'],
            'governorate_id'=>['nullable','integer','exists:governorates,id'],
            'geo_cell_id'=>['nullable','integer','exists:geo_cells,id'],
            'address'=>['nullable','string','max:500'],
            'latitude'=>['nullable','numeric','between:-90,90','required_with:longitude'],
            'longitude'=>['nullable','numeric','between:-180,180','required_with:latitude'],
            'cover_image_url'=>['nullable','url','max:500'],
        ]);
    }

    private function unitRules(Request $request, Development $development, ?DevelopmentUnit $unit=null): array
    {
        return $request->validate([
            'code'=>['required','string','max:80',Rule::unique('development_units','code')->where(fn($q)=>$q->where('development_id',$development->id))->ignore($unit?->id)],
            'title'=>['required','string','min:2','max:180'],
            'unit_type'=>['required',Rule::in(['apartment','villa','townhouse','office','shop','land','other'])],
            'floor_label'=>['nullable','string','max:80'],'bedrooms'=>['nullable','integer','min:0','max:100'],'bathrooms'=>['nullable','numeric','min:0','max:100'],
            'area_m2'=>['required','numeric','gt:0','max:10000000'],'price'=>['nullable','numeric','min:0','max:9999999999999999'],
            'currency'=>['required','string','size:3'],'status'=>['required',Rule::in(['available','reserved','sold','hidden'])],
            'available_from'=>['nullable','date'],'description'=>['nullable','string','max:10000'],
        ]);
    }

    private function normalizeLocation(array $v, ?Development $current=null): array
    {
        if(isset($v['geo_cell_id'])){
            $cell=DB::table('geo_cells')->where('id',$v['geo_cell_id'])->first();
            if(!$cell) throw ValidationException::withMessages(['geo_cell_id'=>['Unknown geographic cell.']]);
            if(isset($v['governorate_id']) && (int)$v['governorate_id']!==(int)$cell->governorate_id) throw ValidationException::withMessages(['governorate_id'=>['The governorate must match the selected cell.']]);
            $v['governorate_id']=(int)$cell->governorate_id;
        }
        $lat=$v['latitude']??$current?->latitude;$lng=$v['longitude']??$current?->longitude;
        if($lat!==null && $lng!==null && DB::connection()->getDriverName()==='pgsql'){
            $row=DB::selectOne('SELECT id, governorate_id FROM geo_cells WHERE is_active = TRUE AND ST_Covers(boundary, ST_SetSRID(ST_MakePoint(?, ?), 4326)) ORDER BY id ASC LIMIT 1',[(float)$lng,(float)$lat]);
            if($row){$v['geo_cell_id']=(int)$row->id;$v['governorate_id']=(int)$row->governorate_id;}
        }
        return $v;
    }

    private function developerData(Developer $d, bool $includeProjects=false): array
    {
        $data=['id'=>$d->id,'name'=>$d->name,'slug'=>$d->slug,'description'=>$d->description,'website'=>$d->website,'phone'=>$d->phone,'email'=>$d->email,'logo_url'=>$d->logo_url,'status'=>$d->status,'projects_count'=>(int)($d->published_projects_count??$d->developments_count??0)];
        if($includeProjects && $d->relationLoaded('developments')) $data['projects']=$d->developments->map(fn(Development $p)=>$this->projectData($p,false))->values();
        return $data;
    }

    private function projectData(Development $d, bool $includeUnits=false): array
    {
        $data=['id'=>$d->id,'developer_id'=>$d->developer_id,'developer'=>$d->relationLoaded('developer')&&$d->developer?$this->developerData($d->developer):null,'name'=>$d->name,'slug'=>$d->slug,'description'=>$d->description,'status'=>$d->status,'completion_status'=>$d->completion_status,'expected_completion_date'=>$d->expected_completion_date?->toDateString(),'governorate_id'=>$d->governorate_id,'governorate_name'=>$d->relationLoaded('governorate')?$d->governorate?->name_ar:null,'geo_cell_id'=>$d->geo_cell_id,'geo_cell_name'=>$d->relationLoaded('geoCell')?$d->geoCell?->name_ar:null,'address'=>$d->address,'latitude'=>$d->latitude,'longitude'=>$d->longitude,'cover_image_url'=>$d->cover_image_url,'published_at'=>$d->published_at?->toIso8601String(),'units_count'=>(int)($d->units_count??($d->relationLoaded('units')?$d->units->count():$d->units()->count())),'available_units_count'=>(int)($d->available_units_count??$d->units()->where('status','available')->count())];
        if($includeUnits && $d->relationLoaded('units')) $data['units']=$d->units->map(fn(DevelopmentUnit $u)=>$this->unitData($u))->values();
        return $data;
    }

    private function unitData(DevelopmentUnit $u): array
    {
        return ['id'=>$u->id,'development_id'=>$u->development_id,'code'=>$u->code,'title'=>$u->title,'unit_type'=>$u->unit_type,'floor_label'=>$u->floor_label,'bedrooms'=>$u->bedrooms,'bathrooms'=>$u->bathrooms,'area_m2'=>$u->area_m2,'price'=>$u->price,'currency'=>$u->currency,'status'=>$u->status,'available_from'=>$u->available_from?->toDateString(),'description'=>$u->description];
    }
}
