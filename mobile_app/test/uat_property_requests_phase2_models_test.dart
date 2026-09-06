import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/property_requests/domain/property_request_models.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';

void main(){test('parses request suggestions and eligible properties',(){final model=PropertyRequestModel.fromJson({'id':7,'operation_type':'sale','property_type':'apartment','governorate':'صنعاء','budget_min':'100','budget_max':200,'currency':'YER','active_duration_days':30,'status':'matched','suggestions_count':1,'suggestions':[{'id':4,'property_id':9,'suggested_by_name':'Broker','property':{'id':9,'title':'Home','price':'150','currency':'YER'}}],'eligible_properties':[{'id':9,'title':'Home','price':150,'currency':'YER'}]});expect(model.status,'matched');expect(model.canClose,isTrue);expect(model.propertyTypeLabel,'شقة');expect(model.suggestions.single.propertyId,9);expect(model.eligibleProperties.single.title,'Home');});}

test('notification retains suggestion deep-link data',(){final item=AppNotificationItem.fromJson({'id':1,'type':'property_suggestion','title':'Suggestion','entity_type':'property_suggestion','entity_id':4,'data':{'property_request_id':7,'property_id':9}});expect(item.data['property_id'],9);});

test('property type API codes have Arabic presentation labels',(){expect(propertyTypeArabicLabel('apartment'),'شقة');expect(propertyTypeArabicLabel('house'),'منزل');expect(propertyTypeArabicLabel('villa'),'فيلا');expect(propertyTypeArabicLabel('land'),'أرض');expect(propertyTypeArabicLabel('shop'),'محل');expect(propertyTypeArabicLabel('office'),'مكتب');expect(propertyTypeArabicLabel('farm'),'مزرعة');expect(propertyTypeArabicLabel('future_type'),'future_type');});

test('parses structured request region identifiers',(){final region=RequestRegionOption.fromJson({'id':12,'name_ar':'حدة','governorate':{'id':3,'name_ar':'صنعاء'}});expect(region.cellId,12);expect(region.governorateId,3);expect(region.cellName,'حدة');});
