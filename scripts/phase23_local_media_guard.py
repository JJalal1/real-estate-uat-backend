#!/usr/bin/env python3
"""Fail-closed boundaries for one disposable ordinary-app media journey."""
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TREES = {'mobile_app': '62e39d1cdb1057068e60f3f64f56cc6d9d5a7b0e',
         'backend-api-runtime': '76dcc5b61ed2bf55d05935289d09885182fef96e'}
EXACT = {
    'PHASE23_LOCAL_MEDIA': 'true', 'APP_ENV': 'local',
    'APP_URL': 'http://10.0.2.2:8000', 'APP_ENVIRONMENT': 'local',
    'API_BASE_URL': 'http://10.0.2.2:8000/api',
    'APP_SHARE_BASE_URL': 'http://10.0.2.2:8000',
    'DB_CONNECTION': 'pgsql', 'DB_HOST': '127.0.0.1', 'DB_PORT': '5432',
    'DB_DATABASE': 'phase23_local_media_ci', 'DB_USERNAME': 'postgres',
    'DB_PASSWORD': '', 'DB_URL': '', 'DB_SEARCH_PATH': 'public,extensions',
    'UAT_CLOUD_STORAGE_ENABLED': 'false', 'PUSH_NOTIFICATIONS_ENABLED': 'false',
    'UAT_TEST_OTP_ENABLED': 'false', 'UAT_WAVE3_FIXTURES_ENABLED': 'false',
    'UAT_CITY_DEMO_SEED_ENABLED': 'false', 'QUEUE_CONNECTION': 'sync',
    'MAIL_MAILER': 'array', 'FILESYSTEM_DISK': 'local', 'CACHE_STORE': 'file',
    'SESSION_DRIVER': 'file',
}
EMPTY = ('DATABASE_URL', 'WHATSAPP_PHONE_NUMBER_ID', 'WHATSAPP_ACCESS_TOKEN',
         'WHATSAPP_AUTH_TEMPLATE', 'SUPABASE_URL', 'SUPABASE_STORAGE_SERVER_KEY',
         'SUPABASE_STORAGE_PUBLISHABLE_KEY', 'FCM_SERVICE_ACCOUNT_FILE',
         'FCM_SERVICE_ACCOUNT_JSON_BASE64', 'OPENAI_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS',
         'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'POSTMARK_API_KEY', 'RESEND_API_KEY')


def environment_guard(env):
    for key, value in EXACT.items():
        if env.get(key) != value:
            raise ValueError('unsafe_local_fixture_environment:' + key)
    if any(env.get(key, '') for key in EMPTY):
        raise ValueError('external_service_configuration_forbidden')
    if not (env.get('GITHUB_ACTIONS') == 'true'
            and env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend'
            and env.get('GITHUB_REF') == 'refs/heads/work/phase23-acceptance-20261111'
            and env.get('GITHUB_EVENT_NAME') == 'push'
            and re.fullmatch('[0-9a-f]{40}', env.get('GITHUB_SHA', ''))
            and env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA')
            and re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_ID', ''))):
        raise ValueError('explicit_disposable_ci_context_required')
    return True


def guard(env, root=ROOT):
    environment_guard(env)
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True, timeout=30).strip()
    if git('rev-parse', 'HEAD') != env['GITHUB_SHA']:
        raise ValueError('checkout_mismatch')
    for component, tree in TREES.items():
        if git('rev-parse', 'HEAD:' + component) != tree:
            raise ValueError('reviewed_product_tree_changed')
    if git('diff', '--name-only', 'HEAD', '--', *TREES):
        raise ValueError('product_worktree_changed')
    backend = root / 'backend-api-runtime'
    if (backend / 'bootstrap/cache/config.php').exists():
        raise ValueError('cached_runtime_config_forbidden')
    dotenv = backend / '.env'
    if dotenv.exists() and any(line.strip() and not re.fullmatch(r'APP_KEY=(?:base64:[A-Za-z0-9+/=]+)?', line)
                               for line in dotenv.read_text().splitlines()):
        raise ValueError('dotenv_must_only_contain_disposable_key')
    return {'marker': 'AQER_LOCAL_MEDIA_FIXTURE_V1', 'source_sha': env['GITHUB_SHA'],
            'run_id': env['GITHUB_RUN_ID'], 'product_trees': TREES,
            'api': EXACT['API_BASE_URL'], 'database': EXACT['DB_DATABASE']}


if __name__ == '__main__':
    import json
    print(json.dumps(guard(os.environ), sort_keys=True))
