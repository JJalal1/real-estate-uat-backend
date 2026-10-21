import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'wave3_fakes.dart';

class Wave6Recovery extends ListingRecoveryStore {
  Wave6Recovery([this.snapshot]);
  Map<String,dynamic>? snapshot;
  @override
  Future<Map<String,dynamic>?> read(int userId,int? listingId) async=>snapshot;
  @override
  Future<void> write(int userId,int? listingId,Map<String,dynamic> data,List<String> paths) async {
    snapshot=Map<String,dynamic>.from(jsonDecode(jsonEncode({...data,'image_paths':paths})) as Map);
  }
  @override
  Future<void> clear(int userId,int? listingId) async {snapshot=null;}
}

class Wave6Drafts implements ListingAccountDraftRepository {
  final drafts=<String,ListingAccountDraft>{};
  final saves=<Map<String,dynamic>>[];
  @override
  Future<List<ListingAccountDraft>> list() async=>drafts.values.toList().reversed.toList();
  @override
  Future<ListingAccountDraft> get(String key) async=>drafts[key]!;
  @override
  Future<ListingAccountDraft> save(String key,Map<String,dynamic> payload,int revision,{int? propertyId}) async {
    final old=drafts[key];
    if((old?.revision??0)!=revision)throw StateError('revision conflict');
    final copy=Map<String,dynamic>.from(jsonDecode(jsonEncode(payload)) as Map);saves.add(copy);
    return drafts[key]=ListingAccountDraft(key:key,revision:revision+1,payload:copy,images:old?.images??{},propertyId:propertyId??old?.propertyId,title:(copy['fields'] as Map?)?['title']?.toString()??'مسودة محفوظة',progress:40);
  }
  @override
  Future<ListingAccountDraft> upload(String key,String imageKey,String path,int revision) async {
    final old=drafts[key]!;return drafts[key]=ListingAccountDraft(key:key,revision:revision+1,payload:old.payload,propertyId:old.propertyId,images:{...old.images,imageKey:'https://fixture.invalid/$imageKey'});
  }
  @override
  Future<ListingAccountDraft> removeImage(String key,String imageKey,int revision) async {
    final old=drafts[key]!,images=Map<String,String>.from(drafts[key]!.images)..remove(imageKey);
    return drafts[key]=ListingAccountDraft(key:key,revision:revision+1,payload:old.payload,propertyId:old.propertyId,images:images);
  }
  @override
  Future<void> delete(String key) async {drafts.remove(key);}
  @override
  Future<Uint8List> photo(String url) async=>Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
}

PropertyDetails wave6Property(int id,{String type='apartment',String purpose='sale',double price=20000000,double? area=120,String currency='YER'})=>PropertyDetails.fromJson({
  'id':id,'title':'عقار للمقارنة $id','type':type,'purpose':purpose,'price':price,'currency':currency,'monthly_rent':purpose=='rent'?price:null,
  'area_value':area,'area_unit':'sqm','bedrooms':id==11?3:4,'bathrooms':2,'floor_number':'2','has_parking':id==11,'has_elevator':false,'building_facade':'north',
  'address':id==11?'صنعاء، حدة':'صنعاء، شملان','latitude':15.36+id*.001,'longitude':44.19+id*.001,'status':'published','availability_status':'available',
});
class Wave6Properties extends Wave3PropertiesFake {
  @override
  Future<List<PropertyDetails>> myListings() async=>[];
  @override
  Future<PropertyDetails> details(int id) async=>wave6Property(id);
  @override
  Future<PropertySaiEnvelope> sai(int id) async=>const PropertySaiEnvelope();
  @override
  Future<PropertySaiManagement> saiPolicy(String purpose) async=>PropertySaiManagement(configured:false,advertiserType:'broker',purpose:purpose,
    fixedRatePercent:purpose=='rent'?20:1,brokerMaxRatePercent:purpose=='rent'?100:5,professionalPlatformSharePercent:20,fallbackPlatformSharePercent:100);
}
class Wave6Ai extends Wave3AiFake {
  Completer<Map<String,dynamic>>? descriptionResult;
  String? rentalConditionsDraftKey;
  @override
  Future<Map<String,dynamic>> rentalConditions(List<Map<String,dynamic>> conditions,{int? propertyId,String? draftKey}) async {
    rentalConditionsDraftKey=draftKey;
    return {'rental_conditions':conditions,'text':'إيجار مقدم لثلاثة أشهر.','requires_review':true};
  }
  @override
  Future<Map<String,dynamic>> description(Map<String,dynamic> facts,{int? propertyId,String? draftKey, String sourceDescription = ''}) async=>
    descriptionResult?.future??Future.value({'description':'منزل للبيع في حدة بصنعاء. يضم ثلاث غرف نوم وحمامين.'});
  @override
  Future<Map<String,dynamic>> prepareListing(String message,Map<String,dynamic> facts,{int? propertyId,String? draftKey}) async=>{
    'source':'ai','requires_review':true,'fields':{'type':'shop','purpose':'rent','governorate':'صنعاء','district':'حدة','area_value':65,'area_unit':'sqm',
      'monthly_rent':75000,'sai_amount_type':'percentage','broker_sai_rate_percent':50,'rental_conditions':[{'kind':'advance','months':3}]},
    'copy':{'title':'محل للإيجار في حدة','description':'محل للإيجار في حدة بصنعاء. تبلغ مساحته 65 م².'},
  };
}
