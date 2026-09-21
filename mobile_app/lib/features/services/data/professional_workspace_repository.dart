import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';

final professionalWorkspaceRepositoryProvider = Provider<ProfessionalWorkspaceRepository>((ref) {
  return ProfessionalWorkspaceRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

final professionalWorkspaceProvider = FutureProvider.autoDispose<ProfessionalWorkspace>((ref) {
  return ref.watch(professionalWorkspaceRepositoryProvider).load();
});

class ProfessionalWorkspaceRepository {
  ProfessionalWorkspaceRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<ProfessionalWorkspace> load() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/professional/workspace',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) throw StateError('Invalid professional workspace response.');
    return ProfessionalWorkspace.fromJson(data);
  }
}

class ProfessionalWorkspace {
  const ProfessionalWorkspace({
    required this.publisherLabel,
    required this.totalListings,
    required this.publishedListings,
    required this.draftListings,
    required this.pendingListings,
    required this.returnedListings,
    required this.favorites,
    required this.conversations,
    required this.unreadConversations,
    required this.activeViewings,
    required this.activeAgreements,
    required this.corrections,
    required this.staleListings,
  });

  final String publisherLabel;
  final int totalListings;
  final int publishedListings;
  final int draftListings;
  final int pendingListings;
  final int returnedListings;
  final int favorites;
  final int conversations;
  final int unreadConversations;
  final int activeViewings;
  final int activeAgreements;
  final List<WorkspaceListingAttention> corrections;
  final List<WorkspaceListingAttention> staleListings;

  factory ProfessionalWorkspace.fromJson(Map<String, dynamic> json) {
    final listings = _map(json['listings']);
    final activity = _map(json['customer_activity']);
    final attention = _map(json['needs_attention']);
    return ProfessionalWorkspace(
      publisherLabel: json['publisher_label']?.toString() ?? 'معلن موثق',
      totalListings: _int(listings['total']),
      publishedListings: _int(listings['published']),
      draftListings: _int(listings['draft']),
      pendingListings: _int(listings['pending']),
      returnedListings: _int(listings['returned_for_correction']),
      favorites: _int(activity['favorites']),
      conversations: _int(activity['conversations']),
      unreadConversations: _int(activity['unread_conversations']),
      activeViewings: _int(activity['active_viewings']),
      activeAgreements: _int(activity['active_agreements']),
      corrections: _rows(attention['correction_listings']),
      staleListings: _rows(attention['stale_published_listings']),
    );
  }
}

class WorkspaceListingAttention {
  const WorkspaceListingAttention({required this.id, required this.title, this.reason});
  final int id;
  final String title;
  final String? reason;

  factory WorkspaceListingAttention.fromJson(Map<String, dynamic> json) => WorkspaceListingAttention(
        id: _int(json['id']),
        title: json['title']?.toString() ?? 'إعلان',
        reason: json['reason']?.toString(),
      );
}

Map<String, dynamic> _map(dynamic value) => value is Map<String, dynamic>
    ? value
    : value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};

List<WorkspaceListingAttention> _rows(dynamic value) => value is List
    ? value.whereType<Map<String, dynamic>>().map(WorkspaceListingAttention.fromJson).toList(growable: false)
    : const [];

int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
