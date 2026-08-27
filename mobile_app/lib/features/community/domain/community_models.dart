class ListingCommentItem {
  const ListingCommentItem({
    required this.id,
    required this.propertyId,
    required this.authorName,
    required this.body,
    required this.status,
    required this.isOwner,
    this.authorUserId,
    this.editedAt,
    this.createdAt,
  });

  final int id;
  final int propertyId;
  final int? authorUserId;
  final String authorName;
  final String body;
  final String status;
  final bool isOwner;
  final DateTime? editedAt;
  final DateTime? createdAt;

  factory ListingCommentItem.fromJson(Map<String, dynamic> json) {
    return ListingCommentItem(
      id: _int(json['id']),
      propertyId: _int(json['property_id']),
      authorUserId: _nullableInt(json['author_user_id']),
      authorName: json['author_name']?.toString() ?? 'مستخدم',
      body: json['body']?.toString() ?? '',
      status: json['status']?.toString() ?? 'visible',
      isOwner: json['is_owner'] == true || json['is_owner'] == 1,
      editedAt: _date(json['edited_at']),
      createdAt: _date(json['created_at']),
    );
  }
}

class MyAdvertiserRating {
  const MyAdvertiserRating({
    required this.id,
    required this.rating,
    required this.status,
    this.comment,
  });

  final int id;
  final int rating;
  final String status;
  final String? comment;

  factory MyAdvertiserRating.fromJson(Map<String, dynamic> json) {
    return MyAdvertiserRating(
      id: _int(json['id']),
      rating: _int(json['rating']),
      status: json['status']?.toString() ?? 'visible',
      comment: _nullable(json['comment']),
    );
  }
}

class AdvertiserRatingSummary {
  const AdvertiserRatingSummary({
    required this.advertiserId,
    required this.advertiserName,
    required this.average,
    required this.count,
    required this.distribution,
    this.myRating,
  });

  final int advertiserId;
  final String advertiserName;
  final double average;
  final int count;
  final Map<int, int> distribution;
  final MyAdvertiserRating? myRating;

  factory AdvertiserRatingSummary.fromJson(Map<String, dynamic> json) {
    final rawDistribution = json['distribution'];
    final distribution = <int, int>{};
    if (rawDistribution is Map) {
      for (final entry in rawDistribution.entries) {
        final key = int.tryParse(entry.key.toString());
        if (key != null) {
          distribution[key] = _int(entry.value);
        }
      }
    }
    final mine = json['my_rating'];
    return AdvertiserRatingSummary(
      advertiserId: _int(json['advertiser_id']),
      advertiserName: json['advertiser_name']?.toString() ?? 'المعلن',
      average: _double(json['average']),
      count: _int(json['count']),
      distribution: distribution,
      myRating: mine is Map<String, dynamic>
          ? MyAdvertiserRating.fromJson(mine)
          : null,
    );
  }
}

int _int(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  return _int(value);
}

double _double(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _date(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
