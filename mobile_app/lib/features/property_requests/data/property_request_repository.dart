import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/property_request_models.dart';

final propertyRequestRepositoryProvider=Provider((ref)=>PropertyRequestRepository(ref.watch(dioProvider),ref.watch(authRepositoryProvider)));
final myPropertyRequestsProvider=FutureProvider.autoDispose((ref)=>ref.watch(propertyRequestRepositoryProvider).mine());
final researcherRequestsProvider=FutureProvider.autoDispose((ref)=>ref.watch(propertyRequestRepositoryProvider).researcher());

class PropertyRequestRepository {
  PropertyRequestRepository(this._dio,this._auth); final Dio _dio; final AuthRepository _auth;
  Future<Options> _options()=>_auth.requiredAuthOptions();
  Future<List<PropertyRequestModel>> mine() async=>_list((await _dio.get<Map<String,dynamic>>('/property-requests',options:await _options())).data);
  Future<PropertyRequestModel> show(int id) async=>_one((await _dio.get<Map<String,dynamic>>('/property-requests/$id',options:await _options())).data);
  Future<PropertyRequestModel> create(Map<String,dynamic> data) async=>_one((await _dio.post<Map<String,dynamic>>('/property-requests',data:data,options:await _options())).data);
  Future<PropertyRequestModel> update(int id,Map<String,dynamic> data) async=>_one((await _dio.patch<Map<String,dynamic>>('/property-requests/$id',data:data,options:await _options())).data);
  Future<PropertyRequestModel> close(int id) async=>_one((await _dio.post<Map<String,dynamic>>('/property-requests/$id/close',options:await _options())).data);
  Future<List<RequestRegionOption>> regions() async {final response=await _dio.get<Map<String,dynamic>>('/regions/cells');return (response.data?['data'] as List<dynamic>? ?? const []).whereType<Map<String,dynamic>>().map(RequestRegionOption.fromJson).where((item)=>item.cellId>0&&item.governorateId>0).toList();}
  Future<List<PropertyRequestModel>> researcher() async=>_list((await _dio.get<Map<String,dynamic>>('/researcher-requests',options:await _options())).data);
  Future<PropertyRequestModel> researcherShow(int id) async=>_one((await _dio.get<Map<String,dynamic>>('/researcher-requests/$id',options:await _options())).data);
  Future<PropertySuggestionModel> suggest(int requestId,int propertyId,{String? note}) async {final body=(await _dio.post<Map<String,dynamic>>('/researcher-requests/$requestId/suggestions',data:{'property_id':propertyId,if(note?.trim().isNotEmpty==true)'note':note!.trim()},options:await _options())).data?['data'];if(body is! Map<String,dynamic>)throw StateError('Invalid suggestion response.');return PropertySuggestionModel.fromJson(body);}
  List<PropertyRequestModel> _list(Map<String,dynamic>? body)=>(body?['data'] as List<dynamic>? ?? const []).whereType<Map<String,dynamic>>().map(PropertyRequestModel.fromJson).toList();
  PropertyRequestModel _one(Map<String,dynamic>? body){final data=body?['data'];if(data is! Map<String,dynamic>)throw StateError('Invalid property request response.');return PropertyRequestModel.fromJson(data);}
}
