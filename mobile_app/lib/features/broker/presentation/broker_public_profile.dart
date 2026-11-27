import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../account/domain/yemen_admin_divisions.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../properties/data/property_repository.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';

final brokerGovernorates = YemenAdminDivisions.governorates
    .map((name) => name == 'سقطرى' ? 'أرخبيل سقطرى' : name)
    .toList(growable: false);

const _bioLimit = 150;

class BrokerPublicProfileSummary extends StatelessWidget {
  const BrokerPublicProfileSummary({
    required this.profile,
    this.contact,
    super.key,
  });

  final BrokerProfile profile;
  final Widget? contact;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    final bio = profile.bio?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EbrokerAdvertiserCard(
          name: profile.name,
          identity: switch (profile.type) {
            'broker' || 'office' => profile.typeLabel,
            _ => null,
          },
          rating: profile.rating,
          ratingCount: profile.ratingCount,
          verified: false,
          photoUrl: profile.photoUrl,
          completedDeals: profile.completedDeals,
          activeListings: profile.activeListings,
          action: contact,
        ),
        const SizedBox(height: 16),
        Text(
          'إعلانات أُغلقت: ${profile.soldListings} مباع · ${profile.rentedListings} مؤجر',
          style: body,
        ),
        if (bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(bio, style: body?.copyWith(height: 1.6)),
          ),
        if (profile.governorate case final governorate?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('المحافظة: $governorate', style: body),
          ),
        if (profile.joinedAt case final joinedAt?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('عضو منذ $joinedAt', style: body),
          ),
      ],
    );
  }
}

void invalidateBrokerProfile(WidgetRef ref, int id) {
  ref.invalidate(brokerProfileProvider(id));
  ref.invalidate(brokerDirectoryProvider);
  ref.invalidate(brokerWorkspaceProvider);
  ref.read(propertyDataRevisionProvider.notifier).state++;
}

class BrokerPublicProfileActions extends ConsumerStatefulWidget {
  const BrokerPublicProfileActions({
    required this.profile,
    this.enabled = true,
    super.key,
  });

  final BrokerProfile profile;
  final bool enabled;

  @override
  ConsumerState<BrokerPublicProfileActions> createState() =>
      _BrokerPublicProfileActionsState();
}

class _BrokerPublicProfileActionsState
    extends ConsumerState<BrokerPublicProfileActions> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null ||
        user.id != widget.profile.id ||
        !user.canCreateListing ||
        !user.canEditPublicProfile) {
      return const SizedBox.shrink();
    }
    final enabled = widget.enabled && !_uploading;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          EbrokerFilledButton.icon(
            onPressed: enabled ? () => _edit(bioOnly: true) : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('تعديل النبذة'),
          ),
          EbrokerFilledButton.icon(
            onPressed: enabled ? _photo : null,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_uploading ? 'جارٍ رفع الصورة…' : 'تغيير الصورة العامة'),
          ),
          if (user.hasMarketplaceProfessionalProfile)
            TextButton.icon(
              onPressed: enabled ? () => _edit(bioOnly: false) : null,
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('المحافظة واسم المكتب'),
            ),
        ],
      ),
    );
  }

  Future<void> _edit({required bool bioOnly}) async {
    final id = widget.profile.id;
    final scope = ref.read(accountRequestScopeProvider);
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final repository = ref.read(brokerRepositoryProvider);
    final saved = await showActorDialog<bool>(
      context: context,
      ref: ref,
      barrierDismissible: false,
      builder: (_) => _EditPublicProfileDialog(
        profile: widget.profile,
        repository: repository,
        bioOnly: bioOnly,
        canSave: () => _ownsProfile(scope, epoch, id),
      ),
    );
    if (saved != true || !mounted || !_ownsProfile(scope, epoch, id)) return;
    invalidateBrokerProfile(ref, id);
    if (!bioOnly) {
      try {
        await ref.read(authControllerProvider.notifier).refresh();
      } catch (error) {
        if (mounted && _ownsProfile(scope, epoch, id)) _showError(error);
      }
    }
  }

  Future<void> _photo() async {
    if (_uploading) return;
    final id = widget.profile.id;
    final scope = ref.read(accountRequestScopeProvider);
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final repository = ref.read(brokerRepositoryProvider);
    const picker = Stage5MediaPicker();
    var paths = <String>[];
    setState(() => _uploading = true);
    try {
      paths = await picker.pickImages();
      if (paths.isEmpty || !mounted || !_ownsProfile(scope, epoch, id)) return;
      await repository.uploadPhoto(paths.first);
      if (mounted && _ownsProfile(scope, epoch, id)) {
        invalidateBrokerProfile(ref, id);
      }
    } catch (error) {
      if (mounted && _ownsProfile(scope, epoch, id)) _showError(error);
    } finally {
      await picker.clearTemporaryFiles(paths).catchError((_) {});
      if (mounted) setState(() => _uploading = false);
    }
  }

  bool _ownsProfile(AccountRequestScope scope, int epoch, int id) =>
      mounted &&
      widget.profile.id == id &&
      scope.isCurrent &&
      epoch == Stage6SecureSessionStore.instance.sessionEpoch &&
      ref.read(authControllerProvider).asData?.value?.id == id;

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyApiError(error))),
    );
  }
}

class _EditPublicProfileDialog extends StatefulWidget {
  const _EditPublicProfileDialog({
    required this.profile,
    required this.repository,
    required this.bioOnly,
    required this.canSave,
  });

  final BrokerProfile profile;
  final BrokerRepository repository;
  final bool bioOnly;
  final bool Function() canSave;

  @override
  State<_EditPublicProfileDialog> createState() =>
      _EditPublicProfileDialogState();
}

class _EditPublicProfileDialogState extends State<_EditPublicProfileDialog> {
  final _form = GlobalKey<FormState>();
  late String _bio;
  late bool _office;
  late String _officeName;
  String? _governorate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _bio = profile.bio ?? '';
    _office = profile.type == 'office';
    _officeName = profile.officeName ?? '';
    final region = YemenAdminDivisions.canonicalGovernorate(
      profile.governorate ?? '',
    );
    _governorate = brokerGovernorates.contains(region) ? region : null;
  }

  Future<void> _save() async {
    if (_saving || !widget.canSave() || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.bioOnly) {
        if (_bio.trim() != (widget.profile.bio ?? '').trim()) {
          await widget.repository.updateProfile(bio: _bio);
        }
      } else {
        await widget.repository.updateProfile(
          governorate: _governorate,
          isOffice: _office,
          officeName: _officeName,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyApiError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.bioOnly ? 'تعديل النبذة' : 'المحافظة واسم المكتب'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.bioOnly)
            TextFormField(
              key: const ValueKey('public-profile-bio'),
              initialValue: _bio,
              enabled: !_saving,
              onChanged: (value) => _bio = value,
              maxLength: _bioLimit,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'نبذة عنك'),
              validator: (value) =>
                  (value?.trim().runes.length ?? 0) > _bioLimit
                  ? 'الحد الأقصى للنبذة 150 حرفًا'
                  : null,
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _governorate,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المحافظة'),
              items: [
                for (final name in brokerGovernorates)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _governorate = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('أعمل باسم مكتب عقاري'),
              value: _office,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _office = value),
            ),
            if (_office)
              TextFormField(
                key: const ValueKey('public-office-name'),
                initialValue: _officeName,
                enabled: !_saving,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'اسم المكتب'),
                onChanged: (value) => _officeName = value,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل اسم المكتب'
                    : null,
              ),
          ],
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      AppButton(
        label: _saving ? 'جارٍ الحفظ' : 'حفظ',
        onPressed: _saving ? null : _save,
      ),
    ],
  );
}
