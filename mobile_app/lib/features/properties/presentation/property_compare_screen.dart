import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_components.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_comparison.dart';
import '../domain/property_sai.dart';
import 'property_compare_actions.dart';

class PropertyCompareScreen extends ConsumerStatefulWidget {
  const PropertyCompareScreen({required this.propertyIds,super.key});
  final List<int> propertyIds;
  @override
  ConsumerState<PropertyCompareScreen> createState()=>_PropertyCompareState();
}
class _PropertyCompareState extends ConsumerState<PropertyCompareScreen>{
  late List<int> _ids;
  late Future<List<_CompareItem>> _future;
  bool _differences=false,_syncing=false;
  final _scrolls=<String,ScrollController>{};
  @override
  void initState(){super.initState();_ids=widget.propertyIds.where((id)=>id>0).toSet().take(4).toList();_future=_load();}
  @override
  void didUpdateWidget(PropertyCompareScreen old){super.didUpdateWidget(old);if(Object.hashAll(old.propertyIds)!=Object.hashAll(widget.propertyIds)){_ids=widget.propertyIds.where((id)=>id>0).toSet().take(4).toList();_future=_load();}}
  @override
  void dispose(){for(final c in _scrolls.values){c.dispose();}super.dispose();}
  ScrollController _scroll(String key)=>_scrolls.putIfAbsent(key,(){final c=ScrollController();c.addListener((){
    if(_syncing || !c.hasClients)return;_syncing=true;
    for(final other in _scrolls.values){if(other!=c && other.hasClients)other.jumpTo(c.offset.clamp(0,other.position.maxScrollExtent).toDouble());}
    _syncing=false;
  });return c;});
  void _reload()=>setState(()=>_future=_load());
  Future<List<_CompareItem>> _load() async{
    final repo=ref.read(propertyRepositoryProvider);
    return Future.wait(_ids.map((id)async{try{
      final p=await repo.details(id);if(p.status!='published' || p.availabilityStatus!='available' || p.financialHold)return _CompareItem(id);
      PropertySaiEnvelope? sai;try{sai=await repo.sai(id);}catch(_){}
      return _CompareItem(id,property:p,sai:sai);
    }catch(_){return _CompareItem(id);}}));
  }
  void _remove(int id){if(ref.read(propertyCompareSelectionProvider).contains(id))ref.read(propertyCompareSelectionProvider.notifier).toggle(id);
    setState((){_ids.remove(id);_future=_future.then((rows)=>rows.where((r)=>r.id!=id).toList());});}
  Future<void> _replace({int? oldId}) async{
    final id=await showModalBottomSheet<int>(context:context,isScrollControlled:true,useSafeArea:true,
      builder:(_)=>_ComparePicker(excluded:_ids.toSet()));
    if(id==null || !mounted)return;
    final selected=ref.read(propertyCompareSelectionProvider),selection=ref.read(propertyCompareSelectionProvider.notifier);
    if(oldId!=null && selected.contains(oldId))selection.toggle(oldId);
    if(!ref.read(propertyCompareSelectionProvider).contains(id))selection.toggle(id);
    setState((){if(oldId==null){_ids.add(id);}else{_ids[_ids.indexOf(oldId)]=id;}_future=_load();});
  }
  @override
  Widget build(BuildContext context){
    ref.listen<int>(propertyDataRevisionProvider,(_,__)=>_reload());
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppAppBar(title:'مقارنة العقارات',actions:[IconButton(onPressed:_reload,tooltip:'تحديث المقارنة',icon:const Icon(Icons.refresh))]),
      body:FutureBuilder<List<_CompareItem>>(future:_future,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        final items=snapshot.data??const <_CompareItem>[];
        if(items.isEmpty)return AppEmptyState(title:'اختر عقارين على الأقل',message:'أضف العقارات التي تريد مقارنتها.',actionLabel:'اختيار عقار',onAction:_replace);
        return LayoutBuilder(builder:(context,constraints){
          final scale=MediaQuery.textScalerOf(context).scale(14)/14;
          final width=items.length==2 && scale<1.5 ? (constraints.maxWidth-40)/2 : scale>=1.5?270.0:210.0;
          Widget columns(String key,List<Widget> children)=>SingleChildScrollView(controller:_scroll(key),scrollDirection:Axis.horizontal,
            child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[for(final child in children)Padding(padding:const EdgeInsetsDirectional.only(end:8),child:SizedBox(width:width,child:child))]));
          final facts=propertyComparisonFacts(items.map((i)=>i.property).toList(),sai:items.map((i)=>i.sai?.sai?.displayText).toList());
          final filtered=facts.where((f)=>!_differences || f.differs).toList();
          final highlights=propertyComparisonHighlights(items.map((i)=>i.property).toList());
          return ListView(padding:const EdgeInsets.fromLTRB(16,16,16,40),children:[
            columns('cards',[for(final item in items)AppSurface(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Row(children:[Expanded(child:Text(item.property==null?'غير متاح':item.property!.type=='land'?'أرض':item.property!.purpose=='rent'?'للإيجار':'للبيع',style:Theme.of(context).textTheme.bodySmall)),
                IconButton(key:ValueKey('remove-compare-${item.id}'),tooltip:'إزالة من المقارنة',onPressed:()=>_remove(item.id),icon:const Icon(Icons.close_rounded,size:19))]),
              ClipRRect(borderRadius:BorderRadius.circular(16),child:AppPropertyMedia(imageUrl:item.property?.mainImage,height:110)),const SizedBox(height:10),
              Text(item.property?.title??'العقار غير متاح حاليًا',maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleSmall),
              if(item.property!=null)...[const SizedBox(height:6),Text(item.property!.address??'الموقع غير مذكور',maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:6),Text(comparisonMoney(item.property!),style:Theme.of(context).textTheme.titleSmall)],
              TextButton.icon(onPressed:item.property==null?null:()=>context.push('/properties/${item.id}'),icon:const Icon(Icons.open_in_new,size:16),label:const Text('عرض العقار')),
              TextButton.icon(onPressed:()=>_replace(oldId:item.id),icon:const Icon(Icons.swap_horiz,size:16),label:const Text('استبدال')),
            ]))]),
            if(_ids.length<4)Align(alignment:AlignmentDirectional.centerStart,child:TextButton.icon(onPressed:_replace,icon:const Icon(Icons.add),label:const Text('إضافة عقار للمقارنة'))),
            const SizedBox(height:12),AppSurface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('الفرق باختصار',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),
              if(highlights.isEmpty)const Text('لا تظهر فروق قابلة للتلخيص من البيانات المتاحة. راجع المواصفات المسجلة أدناه.'),
              for(final line in highlights)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(line)),
            ])),const SizedBox(height:16),
            Wrap(spacing:8,runSpacing:6,children:[ChoiceChip(key:const ValueKey('compare-differences'),label:const Text('الاختلافات فقط'),selected:_differences,onSelected:(_)=>setState(()=>_differences=true)),
              ChoiceChip(key:const ValueKey('compare-all'),label:const Text('كل المواصفات'),selected:!_differences,onSelected:(_)=>setState(()=>_differences=false))]),
            if(filtered.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:20),child:Text('لا توجد اختلافات في المواصفات المسجلة. يمكنك عرض كل المواصفات.')),
            for(final group in const ['معلومات أساسية','السعر والتكاليف','العقار والمبنى','شروط الإيجار','الموقع'])
              if(filtered.any((f)=>f.group==group))Padding(padding:const EdgeInsets.only(top:20),child:AppSurface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(group,style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:10),
                for(final fact in filtered.where((f)=>f.group==group))...[
                  const Divider(height:20),Text(fact.label,style:Theme.of(context).textTheme.labelLarge),const SizedBox(height:8),
                  columns(fact.label,[for(var i=0;i<items.length;i++)Padding(padding:const EdgeInsetsDirectional.only(end:12),child:Text(items[i].property==null?'غير متاح':fact.values[i]??'غير مذكور'))]),
                ],
              ]))),
          ]);
        });
      })));
  }
}
class _CompareItem{
  const _CompareItem(this.id,{this.property,this.sai});
  final int id;final PropertyDetails? property;final PropertySaiEnvelope? sai;
}
class _ComparePicker extends ConsumerStatefulWidget{
  const _ComparePicker({required this.excluded});final Set<int> excluded;
  @override
  ConsumerState<_ComparePicker> createState()=>_ComparePickerState();
}
class _ComparePickerState extends ConsumerState<_ComparePicker>{
  final _text=TextEditingController(),_rows=<PropertySummary>[];bool _busy=true,_more=false;int _page=0,_request=0;String? _error;
  @override
  void initState(){super.initState();Future.microtask(_load);}
  @override
  void dispose(){_text.dispose();super.dispose();}
  Future<void> _load({bool more=false})async{final request=++_request;setState((){_busy=true;_error=null;if(!more)_rows.clear();});
    try{final result=await ref.read(propertyRepositoryProvider).searchListings({if(_text.text.trim().isNotEmpty)'search':_text.text.trim()},page:more?_page+1:1);
      if(!mounted || request!=_request)return;setState((){_rows.addAll(result.$1.where((r)=>!widget.excluded.contains(r.id)));_page=more?_page+1:1;_more=result.$2;_busy=false;});
    }catch(e){if(mounted)setState((){_busy=false;_error='تعذر تحميل العقارات. أعد المحاولة.';});}}
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:SizedBox(height:MediaQuery.sizeOf(context).height*.8,
    child:Padding(padding:EdgeInsets.fromLTRB(18,18,18,MediaQuery.viewInsetsOf(context).bottom+18),child:Column(children:[
      Text('اختر عقارًا للمقارنة',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),
      TextField(controller:_text,decoration:InputDecoration(hintText:'ابحث بالعنوان أو المنطقة',suffixIcon:IconButton(onPressed:()=>_load(),icon:const Icon(Icons.search))),onSubmitted:(_)=>_load()),
      if(_error!=null)TextButton(onPressed:()=>_load(),child:Text(_error!)),
      Expanded(child:ListView(children:[for(final row in _rows)ListTile(leading:SizedBox(width:56,child:AppPropertyMedia(imageUrl:row.mainImage,height:56)),
        title:Text(row.title),subtitle:Text(row.address??''),onTap:()=>Navigator.pop(context,row.id)),
        if(_busy)const Center(child:CircularProgressIndicator()),if(!_busy && _rows.isEmpty && _error==null)const Text('لا توجد عقارات بهذه الشروط.'),
        if(_more && !_busy)TextButton(onPressed:()=>_load(more:true),child:const Text('المزيد')),
      ])),
    ]))));
}
