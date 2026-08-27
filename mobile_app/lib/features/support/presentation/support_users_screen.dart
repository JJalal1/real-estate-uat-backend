import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/access_control_repository.dart';
import '../../account/domain/access_models.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportUsersScreen extends ConsumerStatefulWidget {
  const SupportUsersScreen({super.key});
  @override
  ConsumerState<SupportUsersScreen> createState() => _SupportUsersScreenState();
}

class _SupportUsersScreenState extends ConsumerState<SupportUsersScreen> {
  final _search = TextEditingController();
  bool _loading = false;
  String? _error;
  List<AccessUserSummary> _users = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(accessControlRepositoryProvider)
          .users(search: _search.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _users = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(e);
      });
    }
  }

  Future<void> _open(AccessUserSummary user) async {
    try {
      final data =
          await ref.read(supportRepositoryProvider).userContext(user.id);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
          context: context,
          builder: (_) => _UserContextDialog(contextData: data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('مستخدمو الدعم')),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                      labelText: 'بحث بالاسم أو الهاتف أو البريد',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.arrow_forward))),
                )),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
                child: _users.isEmpty && !_loading
                    ? const Center(child: Text('لا توجد نتائج.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final user = _users[i];
                          return Card(
                              child: ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.person_outline)),
                            title: Text(user.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text([
                              if (user.phone != null) user.phone!,
                              user.email,
                              'الحالة: ${user.accountStatus}'
                            ].join('\n')),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => _open(user),
                          ));
                        },
                      )),
          ]),
        ),
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _UserContextDialog extends StatelessWidget {
  const _UserContextDialog({required this.contextData});
  final SupportUserContext contextData;
  @override
  Widget build(BuildContext context) {
    final user = contextData.user;
    return AlertDialog(
      title: Text(user['name']?.toString() ?? 'المستخدم'),
      content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('الهاتف: ${user['phone'] ?? '-'}'),
                Text('البريد: ${user['email'] ?? '-'}'),
                Text('الحالة: ${user['account_status'] ?? '-'}'),
                Text('نوع الحساب: ${user['account_type'] ?? '-'}'),
                const Divider(height: 24),
                Text(
                    'تذاكر: ${contextData.counts['tickets'] ?? 0} • بلاغات: ${contextData.counts['reports'] ?? 0} • مفتوحة: ${contextData.counts['open'] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...contextData.cases.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.subject),
                    subtitle: Text('${item.reference} • ${item.status}'))),
              ]))),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))
      ],
    );
  }
}
