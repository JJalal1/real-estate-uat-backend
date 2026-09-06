class PropertyRequestModel {
  const PropertyRequestModel({required this.id, required this.operationType, required this.propertyType, required this.governorate, required this.budgetMin, required this.budgetMax, required this.currency, required this.activeDurationDays, required this.status, required this.suggestionsCount, this.governorateId, this.geoCellId, this.district, this.area, this.requestedAreaMin, this.requestedAreaMax, this.rooms, this.additionalSpecifications, this.expiresAt, this.suggestions = const [], this.eligibleProperties = const []});
  final int id; final int? governorateId; final int? geoCellId; final String operationType; final String propertyType; final String governorate; final String? district; final String? area; final double budgetMin; final double budgetMax; final String currency; final int? requestedAreaMin; final int? requestedAreaMax; final int? rooms; final String? additionalSpecifications; final int activeDurationDays; final String status; final DateTime? expiresAt; final int suggestionsCount; final List<PropertySuggestionModel> suggestions; final List<SuggestableProperty> eligibleProperties;
  bool get canEdit => status == 'active'; bool get canClose => status == 'active' || status == 'matched';
  String get operationLabel => operationType == 'sale' ? 'شراء' : 'إيجار';
  String get propertyTypeLabel => propertyTypeArabicLabel(propertyType);
  factory PropertyRequestModel.fromJson(Map<String,dynamic> json) => PropertyRequestModel(id:_int(json['id']),governorateId:_nullableInt(json['governorate_id']),geoCellId:_nullableInt(json['geo_cell_id']),operationType:'${json['operation_type']??''}',propertyType:'${json['property_type']??''}',governorate:'${json['governorate']??''}',district:_text(json['district']),area:_text(json['area']),budgetMin:_double(json['budget_min']),budgetMax:_double(json['budget_max']),currency:'${json['currency']??'YER'}',requestedAreaMin:_nullableInt(json['requested_area_min']),requestedAreaMax:_nullableInt(json['requested_area_max']),rooms:_nullableInt(json['rooms']),additionalSpecifications:_text(json['additional_specifications']),activeDurationDays:_int(json['active_duration_days']),status:'${json['status']??'active'}',expiresAt:DateTime.tryParse('${json['expires_at']??''}'),suggestionsCount:_int(json['suggestions_count']),suggestions:_maps(json['suggestions']).map(PropertySuggestionModel.fromJson).toList(),eligibleProperties:_maps(json['eligible_properties']).map(SuggestableProperty.fromJson).toList());
}

class RequestRegionOption { const RequestRegionOption({required this.governorateId,required this.governorateName,required this.cellId,required this.cellName}); final int governorateId; final String governorateName; final int cellId; final String cellName; factory RequestRegionOption.fromJson(Map<String,dynamic> json){final governorate=json['governorate'] is Map<String,dynamic>?json['governorate'] as Map<String,dynamic>:const <String,dynamic>{};return RequestRegionOption(governorateId:_int(governorate['id']),governorateName:'${governorate['name_ar']??''}',cellId:_int(json['id']),cellName:'${json['name_ar']??''}');} }

class PropertySuggestionModel {
  const PropertySuggestionModel({required this.id, required this.propertyId, required this.suggestedByName, this.note, this.property});
  final int id; final int propertyId; final String suggestedByName; final String? note; final SuggestableProperty? property;
  factory PropertySuggestionModel.fromJson(Map<String,dynamic> json)=>PropertySuggestionModel(id:_int(json['id']),propertyId:_int(json['property_id']),suggestedByName:'${json['suggested_by_name']??''}',note:_text(json['note']),property:json['property'] is Map<String,dynamic>?SuggestableProperty.fromJson(json['property'] as Map<String,dynamic>):null);
}

class SuggestableProperty { const SuggestableProperty({required this.id,required this.title,required this.price,required this.currency,this.address}); final int id; final String title; final double price; final String currency; final String? address; factory SuggestableProperty.fromJson(Map<String,dynamic> json)=>SuggestableProperty(id:_int(json['id']),title:'${json['title']??''}',price:_double(json['price']),currency:'${json['currency']??'YER'}',address:_text(json['address'])); }

List<Map<String,dynamic>> _maps(dynamic value)=>(value as List<dynamic>? ?? const []).whereType<Map<String,dynamic>>().toList(); int _int(dynamic value)=>int.tryParse('$value')??0; int? _nullableInt(dynamic value)=>value==null?null:int.tryParse('$value'); double _double(dynamic value)=>double.tryParse('$value')??0; String? _text(dynamic value){final text=value?.toString().trim();return text==null||text.isEmpty?null:text;}

String propertyTypeArabicLabel(String code) => const <String, String>{
  'apartment': 'شقة',
  'house': 'منزل',
  'villa': 'فيلا',
  'land': 'أرض',
  'shop': 'محل',
  'office': 'مكتب',
  'farm': 'مزرعة',
}[code] ?? code;
