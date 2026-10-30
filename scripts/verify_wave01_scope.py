#!/usr/bin/env python3
"""Keep APK1436 components unchanged outside the owner's six Wave01 requests."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '64c25b1ae6b112ab836b1419166cfbd5d4dd306e'
TREE = '1804ba248c93f3e476a2a4ec6796536b3019a313'
ALLOWED = {
    'backend-api-runtime/app/Http/Controllers/Api/PropertyController.php',
    'backend-api-runtime/app/Http/Controllers/Api/SavedPropertySearchController.php',
    'backend-api-runtime/app/Services/DynamicPropertySchema.php',
    'backend-api-runtime/app/Services/PropertyDiscoveryFilterService.php',
    'backend-api-runtime/app/Services/SavedPropertySearchService.php',
    'backend-api-runtime/app/Services/SmartSearchService.php',
    'mobile_app/lib/core/branding/aqer_brand.dart',
    'mobile_app/lib/core/theme/app_theme.dart',
    'mobile_app/lib/core/widgets/app_components.dart',
    'mobile_app/lib/core/widgets/ebroker_widgets.dart',
    'mobile_app/lib/core/widgets/inline_voice_capture.dart',
    'mobile_app/lib/features/account/presentation/account_screen.dart',
    'mobile_app/lib/features/account/presentation/auth_screen.dart',
    'mobile_app/lib/features/discovery/data/marketplace_repository.dart',
    'mobile_app/lib/features/discovery/data/marketplace_search_session.dart',
    'mobile_app/lib/features/discovery/data/published_listing_suggestions.dart',
    'mobile_app/lib/features/discovery/data/smart_search_session.dart',
    'mobile_app/lib/features/discovery/domain/smart_search_filters.dart',
    'mobile_app/lib/features/discovery/presentation/assisted_search_screen.dart',
    'mobile_app/lib/features/discovery/presentation/home_ai_search_entry.dart',
    'mobile_app/lib/features/discovery/presentation/marketplace_home_screen.dart',
    'mobile_app/lib/features/discovery/presentation/marketplace_search_panel.dart',
    'mobile_app/lib/features/discovery/presentation/marketplace_section_screen.dart',
    'mobile_app/lib/features/discovery/presentation/smart_search_assistant.dart',
    'mobile_app/lib/features/discovery/presentation/smart_search_filter_editor.dart',
    'mobile_app/lib/features/map/presentation/map_screen.dart',
    'mobile_app/lib/features/map/presentation/property_map_results_sheet.dart',
    'mobile_app/lib/features/messages/presentation/conversation_screen.dart',
    'mobile_app/lib/features/properties/data/property_repository.dart',
    'mobile_app/lib/features/properties/domain/property_schema.dart',
    'mobile_app/lib/features/properties/presentation/listing_ai_sheet.dart',
    'mobile_app/lib/features/properties/presentation/listing_draft_entry_screen.dart',
    'mobile_app/lib/features/properties/presentation/listing_editor_screen.dart',
    'mobile_app/lib/features/properties/presentation/property_details_screen.dart',
    'mobile_app/lib/features/properties/presentation/saved_search_builder_screen.dart',
    'mobile_app/lib/features/properties/presentation/saved_searches_screen.dart',
    'mobile_app/lib/features/services/presentation/services_screen.dart',
    'mobile_app/lib/router/app_router.dart',
    # W1-03: only semantic presentation colors; support actions stay protected.
    'mobile_app/lib/features/support/presentation/support_tasks_screen.dart',
    'mobile_app/lib/features/support/presentation/support_workspace_pages.dart',
}

PREFIXES = ('mobile_app/lib/', 'mobile_app/assets/', 'mobile_app/android/',
            'backend-api-runtime/app/', 'backend-api-runtime/database/',
            'backend-api-runtime/resources/', 'backend-api-runtime/routes/',
            'backend-api-runtime/config/')
EXACT = {'mobile_app/pubspec.yaml', 'mobile_app/pubspec.lock',
         'backend-api-runtime/composer.json', 'backend-api-runtime/composer.lock'}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    assert git('rev-parse', BASE + '^{tree}').decode().strip() == TREE, 'Wrong APK1436 source'
    baseline, count = set(), 0
    for entry in git('ls-tree', '-rz', BASE).split(b'\0'):
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        mode, kind, sha = metadata.decode().split()
        path = raw_path.decode()
        baseline.add(path)
        if kind != 'blob' or path in ALLOWED or not (path.startswith(PREFIXES) or path in EXACT):
            continue
        payload = (ROOT / path).read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(payload)).encode() + b'\0' + payload).hexdigest()
        assert actual == sha, 'Protected APK1436 component changed: ' + path
        count += 1
    for prefix in PREFIXES:
        for item in (ROOT / prefix).rglob('*'):
            if item.is_file():
                path = item.relative_to(ROOT).as_posix()
                assert path in baseline or path in ALLOWED, 'Unapproved new component: ' + path
    # Property write/financial/identity methods are outside the discovery change.
    controller = 'backend-api-runtime/app/Http/Controllers/Api/PropertyController.php'
    marker = b'    public function marketplaceLocations(): JsonResponse'
    assert (ROOT / controller).read_bytes().split(marker, 1)[1] == git('show', BASE + ':' + controller).split(marker, 1)[1], 'Property writes changed'
    schema = 'backend-api-runtime/app/Services/DynamicPropertySchema.php'
    actual, original = (ROOT / schema).read_bytes(), git('show', BASE + ':' + schema)
    assert actual.split(b'    public function filters(', 1)[0] == original.split(b'    public function filters(', 1)[0], 'Listing fact/schema applicability changed'
    assert actual.split(b'    public function normalizeFloor(', 1)[1] == original.split(b'    public function normalizeFloor(', 1)[1], 'Listing structural/floor validation changed'
    print(json.dumps({'baseline_source': BASE, 'baseline_tree': TREE,
                      'owner_build': 1436, 'unchanged_components': count,
                      'scope': sorted(ALLOWED), 'verified': True}))


if __name__ == '__main__':
    main()
