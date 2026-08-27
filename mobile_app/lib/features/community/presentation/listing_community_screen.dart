import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_dialogs.dart';

class ListingCommunityScreen extends ConsumerStatefulWidget {
  const ListingCommunityScreen({
    required this.propertyId,
    required this.advertiserId,
    required this.advertiserName,
    super.key,
  });

  final int propertyId;
  final int advertiserId;
  final String advertiserName;

  @override
  ConsumerState<ListingCommunityScreen> createState() =>
      _ListingCommunityScreenState();
}

class _ListingCommunityScreenState
    extends ConsumerState<ListingCommunityScreen> {
  bool _loading = true;
  String? _error;
  List<ListingCommentItem> _comments = const [];
  AdvertiserRatingSummary? _rating;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repository = ref.read(communityRepositoryProvider);
      final comments = await repository.comments(widget.propertyId);
      final rating = await repository.ratingSummary(widget.advertiserId);
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = comments;
        _rating = rating;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.asData?.value;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التعليقات وتقييم المعلن')),
        floatingActionButton: user == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _addComment,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('تعليق'),
              ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorCard(message: _error!, onRetry: _load)
              else ...[
                _ratingCard(user?.id),
                const SizedBox(height: 14),
                if (user == null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.login),
                      title: const Text('سجّل الدخول للمشاركة'),
                      subtitle: const Text(
                        'التعليقات والتقييم والبلاغات تحتاج حساباً فعالاً.',
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => context.push('/auth'),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'التعليقات (${_comments.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    if (user != null)
                      TextButton.icon(
                        onPressed: () => _report(
                          'listing',
                          widget.propertyId,
                          'الإعلان',
                        ),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('بلاغ عن الإعلان'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_comments.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('لا توجد تعليقات بعد.'),
                    ),
                  )
                else
                  ..._comments.map(
                    (comment) => _CommentCard(
                      comment: comment,
                      canReport: user != null && !comment.isOwner,
                      onEdit:
                          comment.isOwner ? () => _editComment(comment) : null,
                      onDelete: comment.isOwner
                          ? () => _deleteComment(comment)
                          : null,
                      onReport: user != null && !comment.isOwner
                          ? () => _report('comment', comment.id, 'التعليق')
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _ratingCard(int? currentUserId) {
    final rating = _rating;
    if (rating == null) {
      return const SizedBox.shrink();
    }
    final canRate =
        currentUserId != null && currentUserId != widget.advertiserId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.advertiserName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                Text(
                  rating.count == 0
                      ? 'لا تقييمات'
                      : '${rating.average.toStringAsFixed(1)} / 5 (${rating.count})',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(
                5,
                (index) => Icon(
                  index < rating.average.round()
                      ? Icons.star
                      : Icons.star_border,
                ),
              ),
            ),
            if (rating.myRating != null) ...[
              const SizedBox(height: 8),
              Text(
                'تقييمك الحالي: ${rating.myRating!.rating}/5'
                '${rating.myRating!.status == 'hidden' ? ' (مخفي بالمراجعة)' : ''}',
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canRate)
                  FilledButton.tonalIcon(
                    onPressed: _rateAdvertiser,
                    icon: const Icon(Icons.star_outline),
                    label: Text(
                      rating.myRating == null ? 'قيّم المعلن' : 'عدّل تقييمك',
                    ),
                  ),
                if (currentUserId != null &&
                    currentUserId != widget.advertiserId)
                  OutlinedButton.icon(
                    onPressed: () => _report(
                      'advertiser',
                      widget.advertiserId,
                      'المعلن',
                    ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('بلاغ عن المعلن'),
                  ),
                if (rating.myRating != null)
                  TextButton.icon(
                    onPressed: _deleteRating,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف تقييمي'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addComment() async {
    final body = await _textDialog(
      title: 'إضافة تعليق',
      hint: 'اكتب تعليقاً واضحاً ومحترماً',
    );
    if (body == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(communityRepositoryProvider)
          .addComment(widget.propertyId, body);
    }, success: 'تمت إضافة التعليق.');
  }

  Future<void> _editComment(ListingCommentItem comment) async {
    final body = await _textDialog(
      title: 'تعديل التعليق',
      hint: 'التعليق',
      initial: comment.body,
    );
    if (body == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(communityRepositoryProvider)
          .updateComment(comment.id, body);
    });
  }

  Future<void> _deleteComment(ListingCommentItem comment) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('حذف التعليق؟'),
            content: const Text('سيختفي التعليق من العرض العام.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await _run(() async {
      await ref.read(communityRepositoryProvider).deleteComment(comment.id);
    });
  }

  Future<void> _rateAdvertiser() async {
    final result = await showAdvertiserRatingDialog(
      context,
      initialRating: _rating?.myRating?.rating ?? 5,
      initialComment: _rating?.myRating?.comment ?? '',
    );
    if (result == null) {
      return;
    }
    await _run(() async {
      await ref.read(communityRepositoryProvider).rateAdvertiser(
            advertiserId: widget.advertiserId,
            rating: result.rating,
            propertyId: widget.propertyId,
            comment: result.comment,
          );
    });
  }

  Future<void> _deleteRating() async {
    await _run(() async {
      await ref
          .read(communityRepositoryProvider)
          .deleteRating(widget.advertiserId);
    });
  }

  Future<void> _report(String targetType, int targetId, String label) async {
    final result = await showCommunityReportDialog(context, label: label);
    if (result == null) {
      return;
    }
    await _run(() async {
      await ref.read(communityRepositoryProvider).report(
            targetType: targetType,
            targetId: targetId,
            reason: result.reason,
            details: result.details,
          );
    }, success: 'تم إرسال البلاغ إلى الدعم.');
  }

  Future<String?> _textDialog({
    required String title,
    required String hint,
    String initial = '',
  }) {
    return showCommunityTextDialog(
      context,
      title: title,
      hint: hint,
      initial: initial,
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (!mounted) {
        return;
      }
      if (success != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success)),
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
    required this.canReport,
    this.onEdit,
    this.onDelete,
    this.onReport,
  });

  final ListingCommentItem comment;
  final bool canReport;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    comment.authorName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (comment.isOwner)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit?.call();
                      } else if (value == 'delete') {
                        onDelete?.call();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  )
                else if (canReport)
                  IconButton(
                    tooltip: 'بلاغ',
                    onPressed: onReport,
                    icon: const Icon(Icons.flag_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comment.body),
            if (comment.editedAt != null) ...[
              const SizedBox(height: 5),
              const Text(
                'تم التعديل',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(message),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
