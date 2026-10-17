import 'property_details.dart';
import 'property_schema.dart';
import 'property_field_options.dart';

class ComparisonFact {
  const ComparisonFact(this.group, this.label, this.values);
  final String group, label;
  final List<String?> values;
  bool get differs => values.toSet().length > 1;
}

String comparisonMoney(PropertyDetails p) => '${formatPropertyAreaValue(p.purpose=='rent' ? p.monthlyRent??p.price : p.price)} ${p.currency}${p.purpose=='rent' && p.monthlyRent!=null ? ' شهريًا':''}';

List<ComparisonFact> propertyComparisonFacts(List<PropertyDetails?> properties, {List<String?> sai = const []}) {
  final rows=<ComparisonFact>[];
  void add(String group,String label,String? Function(PropertyDetails p) read,{String? key}) {
    final values=properties.map((p)=>p==null || (key!=null && !DynamicPropertySchema.applies(key,{'type':p.type,'purpose':p.purpose,'unit_occupies_entire_floor':p.unitOccupiesEntireFloor})) ? null : read(p)).toList();
    if(values.any((v)=>v!=null && v.isNotEmpty))rows.add(ComparisonFact(group,label,values));
  }
  String? boolean(bool? value)=>value==null?null:value?'نعم':'لا';
  const types={'apartment':'شقة','floor':'شقة','house':'منزل','villa':'فيلا','building':'عمارة','land':'أرض','farm':'مزرعة','shop':'محل','office':'مكتب'};
  add('معلومات أساسية','نوع العقار',(p)=>types[p.type]);
  add('معلومات أساسية','الغرض',(p)=>p.purpose=='rent'?'للإيجار':'للبيع');
  add('معلومات أساسية','المساحة',(p)=>p.areaValue!=null?'${formatPropertyAreaValue(p.areaValue!)} ${propertyAreaUnitLabel(p.areaUnit)}':p.areaM2==null?null:'${p.areaM2} م²',key:'area_value');
  add('السعر والتكاليف','السعر',comparisonMoney);
  if(sai.any((v)=>v!=null))rows.add(ComparisonFact('السعر والتكاليف','السعي',List.generate(properties.length,(i)=>i<sai.length?sai[i]:null)));
  add('العقار والمبنى','نوع الملكية',(p)=>p.tenureType==null?null:p.tenureType=='waqf'?'وقف':'حر',key:'tenure_type');
  add('العقار والمبنى','غرف النوم',(p)=>p.bedrooms?.toString(),key:'bedrooms');
  add('العقار والمبنى','الحمامات',(p)=>p.bathrooms?.toString(),key:'bathrooms');
  add('العقار والمبنى','الدور',(p)=>p.floorNumber==null?null:DynamicPropertySchema.floorLabel(p.floorNumber),key:'floor_number');
  add('العقار والمبنى','موضع الوحدة',(p)=>p.unitNumber,key:'unit_number');
  add('العقار والمبنى','الموقف',(p)=>boolean(p.hasParking),key:'has_parking');
  add('العقار والمبنى','المصعد',(p)=>boolean(p.hasElevator),key:'has_elevator');
  add('العقار والمبنى','الواجهة',(p)=>p.buildingFacade==null?null:propertyFacadeLabel(p.buildingFacade),key:'building_facade');
  add('شروط الإيجار','الشروط المحددة',(p)=>p.rentalConditions.isEmpty?null:p.rentalConditions.map((c)=>switch(c['kind']){
    'advance'=>'مقدم ${c['months']} أشهر','duration'=>'مدة ${c['months']} أشهر','guarantor'=>'ضمانة تجارية','deposit'=>'تأمين',_=>c['text']?.toString()??'',
  }).join(' · '),key:'rental_conditions');
  add('الموقع','العنوان',(p)=>p.address);
  return rows;
}

List<String> propertyComparisonHighlights(List<PropertyDetails?> values) {
  final rows=values.whereType<PropertyDetails>().toList();
  if(rows.length<2)return const [];
  final output=<String>[];
  if(rows.map((p)=>p.currency).toSet().length==1 && rows.map((p)=>p.purpose).toSet().length==1 &&
      (rows.first.purpose!='rent' || rows.every((p)=>p.monthlyRent!=null))){
    double price(PropertyDetails p)=>p.purpose=='rent'?p.monthlyRent!:p.price;
    final sorted=List<PropertyDetails>.of(rows)..sort((a,b)=>price(a).compareTo(price(b)));
    if(price(sorted.first)<price(sorted.last))output.add('${sorted.first.title} أقل ${rows.first.purpose=='rent'?'إيجارًا شهريًا':'سعرًا'} بفارق ${formatPropertyAreaValue(price(sorted.last)-price(sorted.first))} ${rows.first.currency}.');
  }
  double? area(PropertyDetails p)=>!DynamicPropertySchema.applies('area_value',{'type':p.type,'purpose':p.purpose})?null:
    p.areaValue!=null?p.areaValue!*(propertyAreaUnitSquareMetres[p.areaUnit??'sqm']??1):p.areaM2?.toDouble();
  if(rows.every((p)=>area(p)!=null)){
    final sorted=List<PropertyDetails>.of(rows)..sort((a,b)=>area(a)!.compareTo(area(b)!));
    if(area(sorted.first)!<area(sorted.last)!)output.add('${sorted.last.title} أكبر مساحة بفارق ${formatPropertyAreaValue(area(sorted.last)!-area(sorted.first)!)} م².');
  }
  if(rows.every((p)=>DynamicPropertySchema.applies('bedrooms',{'type':p.type,'purpose':p.purpose}) && p.bedrooms!=null)){
    final sorted=List<PropertyDetails>.of(rows)..sort((a,b)=>a.bedrooms!.compareTo(b.bedrooms!));
    if(sorted.first.bedrooms!<sorted.last.bedrooms!)output.add('${sorted.last.title} يضم ${sorted.last.bedrooms} غرف نوم مقابل ${sorted.first.bedrooms}.');
  }
  if(rows.every((p)=>DynamicPropertySchema.applies('has_parking',{'type':p.type,'purpose':p.purpose}) && p.hasParking!=null) && rows.map((p)=>p.hasParking).toSet().length>1){
    output.add('يتوفر موقف في ${rows.where((p)=>p.hasParking==true).map((p)=>p.title).join(' و')}، ولا يوجد موقف في ${rows.where((p)=>p.hasParking==false).map((p)=>p.title).join(' و')}.');
  }
  final addresses=rows.map((p)=>p.address?.trim()).whereType<String>().where((a)=>a.isNotEmpty).toSet();
  if(addresses.length>1)output.add('تختلف المواقع: ${addresses.join(' · ')}.');
  return output;
}
