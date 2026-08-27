import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/admin_workspace_repository.dart';
import '../domain/admin_workspace_models.dart';

class PlatformSettingsScreen extends ConsumerStatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  ConsumerState<PlatformSettingsScreen> createState() =>
      _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState
    extends ConsumerState<PlatformSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PlatformSettingItem> _items = const [];
  final Map<String, TextEditingController> _text = {};
  final Map<String, bool> _bool = {};

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
      final rows = await ref.read(adminWorkspaceRepositoryProvider).settings();
      for (final c in _text.values) {
        c.dispose();
      }
      _text.clear();
      _bool.clear();
      for (final item in rows) {
        if (item.valueType == 'boolean') {
          _bool[item.key] = item.value == true;
        } else {
          _text[item.key] =
              TextEditingController(text: item.value?.toString() ?? '');
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _save() async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user?.isPlatformOwner != true &&
        user?.hasPermission('settings.manage') != true) {
      return;
    }
    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{};
      for (final item in _items) {
        values[item.key] = item.valueType == 'boolean'
            ? (_bool[item.key] ?? false)
            : _text[item.key]?.text.trim();
      }
      await ref.read(adminWorkspaceRepositoryProvider).updateSettings(values);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات.')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final canManage = user?.isPlatformOwner == true ||
        user?.hasPermission('settings.manage') == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعدادات المنصة'), actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Card(
                          child: ListTile(
                              leading: Icon(Icons.security_outlined),
                              title: Text('إعدادات آمنة فقط'),
                              subtitle: Text(
                                  'لا تعرض هذه الصفحة كلمات المرور أو مفاتيح API أو بيانات البطاقات الحساسة.'))),
                      const SizedBox(height: 10),
                      ..._items.map((item) => Card(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: item.valueType == 'boolean'
                                  ? SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: _bool[item.key] ?? false,
                                      title: Text(item.labelAr,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800)),
                                      onChanged: canManage
                                          ? (value) => setState(
                                              () => _bool[item.key] = value)
                                          : null)
                                  : TextField(
                                      controller: _text[item.key],
                                      enabled: canManage,
                                      keyboardType: item.valueType == 'integer'
                                          ? TextInputType.number
                                          : TextInputType.text,
                                      decoration: InputDecoration(
                                          labelText: item.labelAr,
                                          helperText: item.group))))),
                      if (canManage) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                                _saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات')),
                      ],
                    ],
                  ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }
}
