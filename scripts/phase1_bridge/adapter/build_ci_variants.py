"""Build remote-UTC plus observed guest-Home logout variants from pinned sources.

This is a source preparation command, not a runner. It never accesses a device,
credentials, API or current aqer files. Original executor files stay untouched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


PINS = {
    'ROOT_C4_EXECUTOR/phase_extensions.py': 'ae28e3fe2f5cb331cdfd40a8c7bc926ca783f91a69359c5b170770cd4f0ad333',
    'ROOT_C2_EXECUTOR_V2/phase_extensions.py': '27a567dbb175140c50a0de705385e56ea5ab4817714d165f06b94cfb8d2159b8',
    'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py': '612d92003702e39cc071815bb4b0ace564eaaeed679bc44cb693defec1e3d79f',
    'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py': '6ad2d841bddb9458752ebd4a79414a7c8c7f4f5d6cab43ac74d7b6c97d8eac44',
    'C2_SOURCE_PROPOSAL/c2_native_roles.py': '789a790fa1bbced95653cf0ecf66190420b814caf15c73189f5b783c5efc183c',
    'promoted_cleanup.py': '4a7752b29cc8b1417e5d82ab94c9113e3687b6b6e37ba995847e387f5d262f67',
}
CAPTURE_PIN = '2ec10b2659ea3f073c47d02c1800cd49b35b58e51ce8430517af74a1ecadcafa'
PREVIOUS_ROLES_PIN = 'cfec7b46f3d37b68c6432893435cd37c970b6713561c644ca6adbc562d635b6c'


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise RuntimeError('exact_variant_patch_precondition_failed')
    return text.replace(before, after, 1)


def support_case_review_transform(name, text):
    """Bind separate actual case/action frames and the source-confirmed return queue."""
    if name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
        text = replace_once(text, "    'submit_confirm': ('broker', 'تأكيد السعي والمتابعة', 'تحديد السعي قبل إرسال الإعلان'),\n    'support_claim': ('support', 'استلام', 'task'),\n    'support_open': ('support', 'متابعة التحقيق', 'fixture'),\n    'return_open': ('support', 'إرجاع للتصحيح', 'fixture'),\n    'return_confirm': ('support', 'تأكيد', 'إرجاع الإعلان للتصحيح'),\n}\npolicy.ACTION_SPEC.update({name: (value[0], value[1]) for name, value in TARGETS.items()})\n", "    'submit_confirm': ('broker', 'تأكيد السعي والمتابعة', 'تحديد السعي قبل إرسال الإعلان'),\n    'support_claim': ('support', 'استلام', 'task'),\n    'support_open': ('support', 'متابعة التحقيق', 'fixture'),\n    'return_open': ('support', 'إرجاع للتصحيح', 'تحقيق الإعلان'),\n    'return_confirm': ('support', 'تأكيد', 'إرجاع الإعلان للتصحيح'),\n}\npolicy.ACTION_SPEC.update({name: (value[0], value[1]) for name, value in TARGETS.items()})\n")
        text = replace_once(text, "         record.get('preceding_exact_fixture_frame_sha256') == preceding_frame and\n         record.get('same_exact_tagged_item_and_button_visually_verified') is True,\n         'actual_fixture_dialog_chain_review_required')\n    eligible = [row for row in rows if row.get('package') == roles.APP and\n                row.get('visible') and row.get('enabled')]\n    indexed = {row.get('path'): row for row in eligible}\n", '         record.get(\'preceding_exact_fixture_frame_sha256\') == preceding_frame and\n         record.get(\'same_exact_tagged_item_and_button_visually_verified\') is True,\n         \'actual_fixture_dialog_chain_review_required\')\n    return _reviewed_anchor_action_node(rows, stage, anchor, record)\n\n\ndef _reviewed_anchor_action_node(rows, stage, anchor, record):\n    """Revalidate one actual visible anchor/action pair, without fixture claims."""\n    eligible = [row for row in rows if row.get(\'package\') == roles.APP and\n                row.get(\'visible\') and row.get(\'enabled\')]\n    indexed = {row.get(\'path\'): row for row in eligible}\n')
        text = replace_once(text, "        self.regular_cycle = 0\n        self.regular_frames = {}\n        self.regular_account_witness = self.regular_logout_receipt = None\n\n    def __repr__(self):\n        return '<C2Executor LOCAL segmented; no acceptance>'\n", "        self.regular_cycle = 0\n        self.regular_frames = {}\n        self.regular_account_witness = self.regular_logout_receipt = None\n        self.case_review_frame = None\n        self.case_header_binding = None\n        self.return_confirmation_frame = None\n        self.return_queue_transition = None\n\n    def __repr__(self):\n        return '<C2Executor LOCAL segmented; no acceptance>'\n")
        text = replace_once(text, "                            'تحقق نشر إعلان: ' + self.title if anchor == 'task' else anchor)\n                rows = self.probe.nodes()\n                try:\n                    if anchor in ('fixture', 'task'):\n                        node = policy.reviewed_action_node(rows, stage, expected, self.tag, record,\n                            native_role=role, auth_uncertain=False)\n                    else:\n", "                            'تحقق نشر إعلان: ' + self.title if anchor == 'task' else anchor)\n                rows = self.probe.nodes()\n                try:\n                    if stage == 'return_open':\n                        need(record.get('same_serialized_support_case_chain_reviewed') is True and\n                             record.get('serialized_case_binding') == self._case_binding() and\n                             record.get('fixture_title_visible_in_action_frame') is False and\n                             record.get('title_path') == self.case_header_binding['path'] and\n                             record.get('title_witness') == self.case_header_binding['witness'],\n                             'actual_separate_case_title_and_return_action_review_required')\n                        node = _reviewed_anchor_action_node(rows, stage, anchor, record)\n                    elif anchor in ('fixture', 'task'):\n                        node = policy.reviewed_action_node(rows, stage, expected, self.tag, record,\n                            native_role=role, auth_uncertain=False)\n                    else:\n")
        text = replace_once(text, '            self._review_observation(stage, record)\n            return record\n        return True\n\n    def _logout(self):\n        result = roles.native_logout_role(self.probe)\n', "            self._review_observation(stage, record)\n            return record\n        return True\n\n    def _case_header(self):\n        self._actor('support')\n        rows = [row for row in self.probe.nodes() if row.get('package') == roles.APP and\n                row.get('visible') and row.get('enabled') and 'تحقيق الإعلان' in policy.names(row)]\n        leaves = [row for row in rows if not any(other['path'].startswith(row['path'] + '.')\n                                                for other in rows)]\n        need(len(leaves) == 1 and policy.sha(leaves[0].get('witness')),\n             'unique_same_support_case_header_required')\n        return {key: leaves[0][key] for key in ('path', 'witness', 'bounds')}\n\n    def _case_binding(self):\n        need(type(self.case_review_frame) is dict and\n             set(self.case_review_frame) == {'file', 'sha256'} and\n             policy.sha(self.case_review_frame['sha256']) and\n             type(self.case_header_binding) is dict and\n             policy.sha(self.delivered_frames.get('support_open')),\n             'actual_reviewed_case_identity_required')\n        return {'kind': 'SERIALIZED_SUPPORT_CASE_IDENTITY', 'fixture_key': self.key,\n                'fixture_tag': self.tag, 'exact_fixture_title': self.title,\n                'property_id': self.property_id,\n                'case_title_review_frame': copy.deepcopy(self.case_review_frame),\n                'case_header_binding': copy.deepcopy(self.case_header_binding),\n                'case_open_frame_sha256': self.delivered_frames['support_open'],\n                'title_to_action_transition_scope': 'SOURCE_SCOPED_SCROLL_WITH_SAME_CASE_HEADER'}\n\n    def _return_queue_observed(self):\n        self._actor('support')\n        names = _names(self.probe.nodes())\n        return ({'تحقيق الإعلانات', 'طلبات التحقيق'} <= names and\n                bool(names & {'لا توجد طلبات معلقة', 'بانتظار الاستلام', 'تم الاستلام - قيد التحقيق'}) and\n                not names & (roles.AUTH_LABELS | {'جارٍ تحميل طلبات التحقيق...', 'إرجاع الإعلان للتصحيح'}) and\n                not any(self.tag in name for name in names))\n\n    def _wait_return_queue(self):\n        # The source pops the case only after the awaited return request succeeds.\n        # The default queue excludes returned cases; do not require their title there.\n        deadline = time.monotonic() + 45\n        while time.monotonic() < deadline:\n            if self._return_queue_observed():\n                self.return_queue_transition = {\n                    'kind': 'RETURN_QUEUE_TRANSITION_PENDING_BROKER_REASON',\n                    'serialized_case_binding': self._case_binding(),\n                    'return_confirmation_frame': copy.deepcopy(self.return_confirmation_frame),\n                    'exact_reason': self.reason, 'investigation_queue_observed': True,\n                    'exact_fixture_absent_from_visible_queue': True,\n                    'return_dialog_closed': True, 'exact_returned_state_proved': False}\n                return\n            time.sleep(.4)\n        need(False, 'source_confirmed_return_queue_not_observed')\n\n    def _logout(self):\n        result = roles.native_logout_role(self.probe)\n")
        text = replace_once(text, "                 record.get('own_task_owner_observed') is True and self.title in names,\n                 'native_support_claim_review_required')\n        elif stage == 'review_case':\n            need(self.title in names and 'إرجاع للتصحيح' in names and\n                 record.get('exact_own_case_title_observed') is True,\n                 'native_exact_review_case_required')\n        elif stage == 'review_returned':\n            need(record.get('native_return_confirmed') is True and\n                 record.get('publication_or_rejection_executed') is False and\n                 record.get('exact_reason') == self.reason, 'native_return_review_required')\n        elif stage == 'review_broker_reason':\n", "                 record.get('own_task_owner_observed') is True and self.title in names,\n                 'native_support_claim_review_required')\n        elif stage == 'review_case':\n            need(self.title in names and 'تحقيق الإعلان' in names and\n                 record.get('exact_own_case_title_observed') is True,\n                 'native_exact_review_case_required')\n        elif stage == 'review_returned':\n            need(self.return_queue_transition is not None and self._return_queue_observed() and\n                 record.get('return_queue_transition') == self.return_queue_transition and\n                 record.get('return_queue_transition_reviewed') is True and\n                 record.get('exact_outcome_deferred_to_broker_reason') is True and\n                 record.get('native_return_confirmed') is False and\n                 record.get('publication_or_rejection_executed') is False and\n                 record.get('exact_reason') == self.reason, 'native_return_review_required')\n        elif stage == 'review_broker_reason':\n")
        text = replace_once(text, "            need(self._rent_sai_preview() == self.rent_sai_readback,\n                 'rent_sai_changed_immediately_before_completion')\n            self._nonimage_input('click', 'العودة إلى النواقص'); p.wait('خيارات المسودة')\n        elif stage in REVIEW_STAGES:\n            pass  # Fresh evidence was checked before reservation; no input here.\n        elif stage == 'full_save':\n", "            need(self._rent_sai_preview() == self.rent_sai_readback,\n                 'rent_sai_changed_immediately_before_completion')\n            self._nonimage_input('click', 'العودة إلى النواقص'); p.wait('خيارات المسودة')\n        elif stage == 'review_case':\n            # Root first accepts the exact case title at the top. The return\n            # control is below evidence/history; reveal it without clicking.\n            self.case_review_frame = {'file': prepared['actual_frame_file'],\n                                      'sha256': prepared['frame_sha256']}\n            self.case_header_binding = self._case_header()\n            self._case_binding()\n            self._actor('support')\n            p.seek('إرجاع للتصحيح')\n            need(self._case_header() == self.case_header_binding and\n                 {'تحقيق الإعلان', 'إرجاع للتصحيح'} <= _names(p.nodes()),\n                 'same_case_return_action_not_observed')\n        elif stage in REVIEW_STAGES:\n            pass  # Fresh evidence was checked before reservation; no input here.\n        elif stage == 'full_save':\n")
        text = replace_once(text, "            # input, NOT proof of the separate unbuilt final-root card extension.\n            p.act('click', node)\n            self.delivered_frames[stage] = record['frame_sha256']\n        elif stage == 'submit_sai_setup':\n            self._actor('broker'); p.wait('تحديد السعي قبل إرسال الإعلان')\n            p.tap('نسبة مئوية %'); p.set('نسبة السعي %', '0'); self._fallback(p.nodes())\n", "            # input, NOT proof of the separate unbuilt final-root card extension.\n            p.act('click', node)\n            self.delivered_frames[stage] = record['frame_sha256']\n            if stage == 'support_claim':\n                # Inbox claim normally opens the investigation queue after reload.\n                p.wait('تحقيق الإعلانات', seconds=45)\n                p.seek(self.title)\n                p.wait('تم الاستلام - قيد التحقيق', seconds=45)\n            elif stage == 'support_open':\n                p.wait('تحقيق الإعلان', seconds=45)\n                p.wait(self.title, seconds=45)\n            elif stage == 'return_confirm':\n                self.return_confirmation_frame = {'file': record['actual_frame_file'],\n                                                  'sha256': record['frame_sha256']}\n                self._wait_return_queue()\n        elif stage == 'submit_sai_setup':\n            self._actor('broker'); p.wait('تحديد السعي قبل إرسال الإعلان')\n            p.tap('نسبة مئوية %'); p.set('نسبة السعي %', '0'); self._fallback(p.nodes())\n")
    if name == 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py':
        text = replace_once(text, "    'same_serialized_editor_chain_reviewed', 'original_fixture_receipt_reviewed',\n    'bound_c4_title_frame', 'photo_visually_unchanged', 'actual_safe_spec_photo_reviewed',\n    'semantic_preview', 'policy_was_visually_reviewed', 'safe_surface_frames',\n    'regular_cycle', 'nonimage_role_witness'})\n\nC1_KEYS = C1_KEYS | {'review_completed_utc'}\nC4_KEYS = C4_KEYS | {'review_completed_utc'}\n", "    'same_serialized_editor_chain_reviewed', 'original_fixture_receipt_reviewed',\n    'bound_c4_title_frame', 'photo_visually_unchanged', 'actual_safe_spec_photo_reviewed',\n    'semantic_preview', 'policy_was_visually_reviewed', 'safe_surface_frames',\n    'regular_cycle', 'nonimage_role_witness', 'same_serialized_support_case_chain_reviewed',\n    'serialized_case_binding', 'fixture_title_visible_in_action_frame',\n    'return_queue_transition', 'return_queue_transition_reviewed',\n    'exact_outcome_deferred_to_broker_reason'})\n\nC1_KEYS = C1_KEYS | {'review_completed_utc'}\nC4_KEYS = C4_KEYS | {'review_completed_utc'}\n")
        text = replace_once(text, "        need('صور الإعلان (1/12)' in names and 'مكتمل' in names,\n             'CAPTURE_HELD_SAFE_SPEC_PHOTO_NOT_OBSERVED')\n        title_text, action_text = None, None\n    elif stage in module.TARGETS:\n        _, action_text, anchor = module.TARGETS[stage]\n        title_text = (executor.title if anchor == 'fixture' else\n", "        need('صور الإعلان (1/12)' in names and 'مكتمل' in names,\n             'CAPTURE_HELD_SAFE_SPEC_PHOTO_NOT_OBSERVED')\n        title_text, action_text = None, None\n    elif stage == 'review_returned':\n        need(executor.return_queue_transition is not None and executor._return_queue_observed(),\n             'CAPTURE_HELD_RETURN_QUEUE_TRANSITION_NOT_OBSERVED')\n        title_text, action_text = 'تحقيق الإعلانات', None\n        need(title_text in names, 'CAPTURE_HELD_RETURN_QUEUE_ANCHOR_NOT_OBSERVED')\n    elif stage in module.TARGETS:\n        _, action_text, anchor = module.TARGETS[stage]\n        title_text = (executor.title if anchor == 'fixture' else\n")
        text = replace_once(text, "            'prior_c4_tagged_title_frame': {'file': 'C1-c4-restored-final-title.png',\n                                           'sha256': executor.c4['restored_frame_sha256']},\n            'fixture_title_visible_in_this_spec_frame': False}\n    return bindings\n\n\n", "            'prior_c4_tagged_title_frame': {'file': 'C1-c4-restored-final-title.png',\n                                           'sha256': executor.c4['restored_frame_sha256']},\n            'fixture_title_visible_in_this_spec_frame': False}\n    if stage == 'return_open':\n        need(executor._case_header() == executor.case_header_binding,\n             'CAPTURE_HELD_REVIEWED_CASE_HEADER_CHANGED')\n        bindings['serialized_case_binding'] = executor._case_binding()\n        bindings['fixture_title_visible_in_action_frame'] = False\n    elif stage == 'review_returned':\n        bindings['return_queue_transition'] = executor.return_queue_transition\n    return bindings\n\n\n")
    return text


def c2_diagnostic_transform(name, text):
    """Add fixed failure location and native input substages; never replay."""
    if name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
        text = replace_once(text, "        self._actor('broker')\n        p = self.probe\n        if kind == 'set':\n", "        controls = {('set', 'الإيجار الشهري بالريال اليمني *'): 'rent',\n                    ('click', 'نسبة مئوية %'): 'sai_mode', ('set', 'نسبة السعي %'): 'sai_rate',\n                    ('click', 'السابق'): 'previous', ('click', 'العودة إلى النواقص'): 'back_gaps',\n                    ('click', 'خيارات المسودة'): 'draft_options', ('click', 'حفظ مسودة'): 'save_draft'}\n        self._diagnostic_operation = {'control': controls.get((kind, label), 'unrecognized'),\n                                      'substage': 'actor_check'}\n        self._actor('broker')\n        p = self.probe\n        self._diagnostic_operation['substage'] = 'field_lookup'\n        if kind == 'set':\n")
        text = replace_once(text, "        result = p.instrument(op, **extra)\n        need(result.get('account_action_delivered') == 'true' and\n", "        self._diagnostic_operation['substage'] = 'instrument'\n        result = p.instrument(op, **extra)\n        self._diagnostic_operation['substage'] = 'delivery_check'\n        need(result.get('account_action_delivered') == 'true' and\n")
        text = replace_once(text, "        if kind == 'set':\n            p.adb('shell', 'input', 'keyevent', '4')\n        p.report['c2_v2_nonimage_input_operations_delivered']", "        if kind == 'set':\n            self._diagnostic_operation['substage'] = 'dismiss_ime'\n            p.adb('shell', 'input', 'keyevent', '4')\n        self._diagnostic_operation['substage'] = 'completed'\n        p.report['c2_v2_nonimage_input_operations_delivered']")
        text = replace_once(text, "            self._nonimage_input('set', 'نسبة السعي %', '0')\n            self.rent_sai_readback = self._rent_sai_preview()", "            self._nonimage_input('set', 'نسبة السعي %', '0')\n            self._diagnostic_operation = {'control': 'rent_sai', 'substage': 'preview'}\n            self.rent_sai_readback = self._rent_sai_preview()")
        text = replace_once(text, '        self.inflight = True\n        try:\n            self._execute(stage, prepared)', "        self.inflight = True\n        self._diagnostic_operation = {'control': 'stage', 'substage': 'execute'}\n        try:\n            self._execute(stage, prepared)")
        text = replace_once(text, "        except Exception:\n            self.failed = True\n            self.inflight = False\n            receipt = self._receipt('BLOCKED_NO_REPLAY', failed=stage)", "        except Exception as error:\n            self.failed = True\n            self.inflight = False\n            # Fixed categories and own code locations only. Never exception\n            # messages/args, frame locals, raw UI values or contact-view hashes.\n            diagnostic = dict(self._diagnostic_operation)\n            diagnostic['stage'] = stage\n            kind = type(error).__name__\n            diagnostic['exception_type'] = kind if kind in {\n                'C2Blocked', 'Blocked', 'AdmissionError', 'BridgeRefused',\n                'TimeoutError', 'OSError', 'ValueError', 'KeyError', 'TypeError'} else 'OtherException'\n            frames, trace = [], error.__traceback__\n            while trace is not None:\n                code = trace.tb_frame.f_code\n                if code.co_filename == __file__:\n                    frames.append({'file': 'ROOT_C2_EXECUTOR_V2/phase_extensions.py',\n                                   'function': code.co_name, 'line': trace.tb_lineno})\n                trace = trace.tb_next\n            diagnostic['source_frames'] = frames[-8:]\n            self.probe.report['c2_v2_stage_failure'] = diagnostic\n            receipt = self._receipt('BLOCKED_NO_REPLAY', failed=stage)")
    return text


def c2_only_entry_transform(name, text):
    """Bind this run's real C1 restoration to C2 in the standard editor.

    Keep historical C4 acceptance separate; never synthesize current C4 state.
    """
    if name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
        text = replace_once(text, "class C2Executor:\n    def __init__(self, probe, original_state, c1_review, c4_review, *,\n                 role_loader=None, request=None, monthly_rent='50000'):\n        # Validation is source-only and reads only parent-provided objects.\n        state = copy.deepcopy(original_state)\n        policy.RemainingLocalFence(state, c1_review)\n        title = c1_review['native_title']\n        need(c4_review.get('manual_review_completed') is True and\n             c4_review.get('c4_accepted') is True and\n             c4_review.get('fixture_key') == state['key'] and\n", "class C2Executor:\n    def __init__(self, probe, original_state, c1_review, c4_review, *,\n                 role_loader=None, request=None, monthly_rent='50000', entry_review=None):\n        # Validation is source-only and reads only parent-provided objects.\n        state = copy.deepcopy(original_state)\n        policy.RemainingLocalFence(state, c1_review)\n        title = c1_review['native_title']\n        if entry_review is not None:\n            # C2 may start from this run's actual C1 restoration. Historical C4\n            # acceptance belongs to Root's separate report, never this fixture.\n            need(c4_review is None and isinstance(entry_review, dict) and\n                 set(entry_review) == {'kind', 'phase', 'privacy_checked', 'manual_review_completed',\n                    'fixture_key', 'fixture_tag', 'restored_title', 'monthly_rent_still_blank',\n                    'property_id', 'same_unpromoted_uuid_verified', 'restored_editor_step',\n                    'restored_frame_sha256', 'restored_photo_frame_sha256', 'entry_mode',\n                    'current_fixture_visually_verified', 'review_completed_utc'} and\n                 entry_review.get('kind') == 'ROOT_ACTUAL_FRAME_REVIEW' and\n                 entry_review.get('phase') == 'C2' and entry_review.get('privacy_checked') is True and\n                 entry_review.get('manual_review_completed') is True and\n                 entry_review.get('current_fixture_visually_verified') is True and\n                 entry_review.get('entry_mode') == 'standard_editor' and\n                 entry_review.get('fixture_key') == state['key'] and\n                 entry_review.get('fixture_tag') == state['tag'] and\n                 entry_review.get('restored_title') == title and\n                 entry_review.get('monthly_rent_still_blank') is True and\n                 entry_review.get('property_id') is None and\n                 entry_review.get('same_unpromoted_uuid_verified') is True and\n                 type(entry_review.get('restored_editor_step')) is int and\n                 entry_review['restored_editor_step'] == 0 and\n                 entry_review.get('restored_frame_sha256') == c1_review['restored_frame_sha256'] and\n                 policy.sha(entry_review.get('restored_photo_frame_sha256')) and\n                 fresh_remote_review(entry_review), 'actual_current_c1_fixture_entry_review_required')\n            self.entry_mode = 'standard_editor'\n            self.fixture_title_frame = {'file': 'C1-restored-title.png',\n                                        'sha256': entry_review['restored_frame_sha256']}\n        else:\n            need(isinstance(c4_review, dict) and c4_review.get('manual_review_completed') is True and\n             c4_review.get('c4_accepted') is True and\n             c4_review.get('fixture_key') == state['key'] and\n")
        text = replace_once(text, "             c4_review['restored_editor_step'] == 0 and\n             policy.sha(c4_review.get('restored_frame_sha256')),\n             'actual_c4_same_unpromoted_restored_review_required')\n        need(monthly_rent == '50000',\n             'synthetic_monthly_rent_shape')\n        self.probe, self.state, self.c1 = probe, state, copy.deepcopy(c1_review)\n        self.c4 = copy.deepcopy(c4_review)\n        self.key, self.tag, self.title = state['key'], state['tag'], title\n        self.reason = 'تصحيح اختبار اصطناعي فقط ' + self.tag\n", "             c4_review['restored_editor_step'] == 0 and\n             policy.sha(c4_review.get('restored_frame_sha256')),\n                 'actual_c4_same_unpromoted_restored_review_required')\n            self.entry_mode = 'completed_review'\n            self.fixture_title_frame = {'file': 'C1-c4-restored-final-title.png',\n                                        'sha256': c4_review['restored_frame_sha256']}\n        need(monthly_rent == '50000',\n             'synthetic_monthly_rent_shape')\n        self.probe, self.state, self.c1 = probe, state, copy.deepcopy(c1_review)\n        self.c4 = copy.deepcopy(c4_review)\n        self.entry_review = copy.deepcopy(entry_review)\n        self.key, self.tag, self.title = state['key'], state['tag'], title\n        self.reason = 'تصحيح اختبار اصطناعي فقط ' + self.tag\n")
        text = replace_once(text, "        need('المواصفات' in _names(rows), 'actual_specification_step_required')\n\n    def register_regular_frame(self, stage, receipt):\n        allowed = {'regular_marketplace', 'regular_messages', 'regular_listing_gate'}\n", '        need(\'المواصفات\' in _names(rows), \'actual_specification_step_required\')\n\n    def _rent_editor_surface(self):\n        """Observe the declared real editor mode; never change it implicitly."""\n        self._actor(\'broker\')\n        names = _names(self.probe.nodes())\n        need(not names & roles.AUTH_LABELS, \'rent_editor_auth_surface_refused\')\n        if self.entry_mode == \'standard_editor\':\n            need({\'خيارات المسودة\', \'إرسال للمراجعة\', \'السابق\'} <= names and\n                 \'العودة إلى النواقص\' not in names,\n                 \'actual_standard_editor_step4_required\')\n        else:\n            need(self.entry_mode == \'completed_review\' and \'العودة إلى النواقص\' in names,\n                 \'actual_completed_review_editor_required\')\n        return True\n\n    def register_regular_frame(self, stage, receipt):\n        allowed = {\'regular_marketplace\', \'regular_messages\', \'regular_listing_gate\'}\n')
        text = replace_once(text, "        if stage == 'review_photo_before_save':\n            self._safe_specs()\n            need('صور الإعلان (1/12)' in names and 'مكتمل' in names and\n                 record.get('evidence_kind') == 'SAFE_SPEC_PHOTO_PLUS_NONIMAGE_POLICY_AND_SERIALIZED_IDENTITY' and\n", "        if stage == 'review_photo_before_save':\n            self._safe_specs()\n            title_key = ('bound_fixture_title_frame' if self.entry_mode == 'standard_editor'\n                         else 'bound_c4_title_frame')\n            other_title_key = ('bound_c4_title_frame' if self.entry_mode == 'standard_editor'\n                               else 'bound_fixture_title_frame')\n            need('صور الإعلان (1/12)' in names and 'مكتمل' in names and\n                 record.get('evidence_kind') == 'SAFE_SPEC_PHOTO_PLUS_NONIMAGE_POLICY_AND_SERIALIZED_IDENTITY' and\n")
        text = replace_once(text, "                 record.get('editor_chain') == self.editor_chain and\n                 record.get('original_fixture_receipt_reviewed') is True and\n                 record.get('bound_c4_title_frame') == {\n                    'file': 'C1-c4-restored-final-title.png',\n                    'sha256': self.c4['restored_frame_sha256']} and\n                 record.get('photo_visually_unchanged') is True and\n                 record.get('actual_safe_spec_photo_reviewed') is True and\n", "                 record.get('editor_chain') == self.editor_chain and\n                 record.get('original_fixture_receipt_reviewed') is True and\n                 record.get(title_key) == self.fixture_title_frame and other_title_key not in record and\n                 record.get('photo_visually_unchanged') is True and\n                 record.get('actual_safe_spec_photo_reviewed') is True and\n")
        text = replace_once(text, "                p.tap('التالي'); p.wait(label)\n            field = p.field('الإيجار الشهري بالريال اليمني *')\n            need(isinstance(field.get('text'), str) and not field['text'].strip() and\n                 'العودة إلى النواقص' in _names(p.nodes()),\n                 'same_blank_rent_completed_review_mode_required')\n        elif stage == 'complete_rent':\n            self._actor('broker')\n", "                p.tap('التالي'); p.wait(label)\n            field = p.field('الإيجار الشهري بالريال اليمني *')\n            need(isinstance(field.get('text'), str) and not field['text'].strip(),\n                 'same_blank_rent_editor_required')\n            self._rent_editor_surface()\n        elif stage == 'complete_rent':\n            self._actor('broker')\n")
        text = replace_once(text, "            self._safe_specs(); p.tap('التالي'); p.wait('الإيجار الشهري بالريال اليمني *')\n            self.rent_sai_recheck = self._rent_sai_preview()\n            need(self.rent_sai_recheck == self.rent_sai_readback and\n                 'العودة إلى النواقص' in _names(p.nodes()),\n                 'rent_sai_changed_after_safe_photo_review')\n            p.report['c2_v2_nonimage_rent_sai_recheck'] = copy.deepcopy(self.rent_sai_recheck)\n        elif stage == 'back_gaps_to_completion':\n", "            self._safe_specs(); p.tap('التالي'); p.wait('الإيجار الشهري بالريال اليمني *')\n            self.rent_sai_recheck = self._rent_sai_preview()\n            need(self.rent_sai_recheck == self.rent_sai_readback,\n                 'rent_sai_changed_after_safe_photo_review')\n            self._rent_editor_surface()\n            p.report['c2_v2_nonimage_rent_sai_recheck'] = copy.deepcopy(self.rent_sai_recheck)\n        elif stage == 'back_gaps_to_completion':\n")
        text = replace_once(text, "            need(self._rent_sai_preview() == self.rent_sai_readback,\n                 'rent_sai_changed_immediately_before_completion')\n            self._nonimage_input('click', 'العودة إلى النواقص'); p.wait('خيارات المسودة')\n        elif stage == 'review_case':\n            # Root first accepts the exact case title at the top. The return\n", "            need(self._rent_sai_preview() == self.rent_sai_readback,\n                 'rent_sai_changed_immediately_before_completion')\n            if self.entry_mode == 'standard_editor':\n                # Standard step4 already exposes the normal explicit save menu.\n                # No completion-mode transition or synthetic click is claimed.\n                self._rent_editor_surface()\n                p.report['c2_v2_completion_transition'] = {\n                    'entry_mode': self.entry_mode, 'native_input_delivered': False,\n                    'outcome': 'not_required_standard_editor_save_surface_observed'}\n            else:\n                self._nonimage_input('click', 'العودة إلى النواقص'); p.wait('خيارات المسودة')\n        elif stage == 'review_case':\n            # Root first accepts the exact case title at the top. The return\n")
        text = replace_once(text, "                'cursor': self.cursor, 'next_stage': STAGES[self.cursor] if self.cursor < len(STAGES) else None,\n                'phase1_accepted': False, 'automatic_replay_allowed': False,\n                'executor_version': 2,\n                'regular_native_logout_confirmed': bool(self.regular_logout_receipt and\n                    self.regular_logout_receipt.get('status') == 'PASS_WITHIN_LOGOUT_UI_SCOPE'),\n", "                'cursor': self.cursor, 'next_stage': STAGES[self.cursor] if self.cursor < len(STAGES) else None,\n                'phase1_accepted': False, 'automatic_replay_allowed': False,\n                'executor_version': 2, 'editor_entry_mode': getattr(self, 'entry_mode', None),\n                'regular_native_logout_confirmed': bool(self.regular_logout_receipt and\n                    self.regular_logout_receipt.get('status') == 'PASS_WITHIN_LOGOUT_UI_SCOPE'),\n")
    if name == 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py':
        text = replace_once(text, "C1_FILE = 'C2_V2_ROOT_C1_REVIEW.json'\nC4_FILE = 'C2_V2_ROOT_C4_REVIEW.json'\nSTAGE_FILE = 'C2_V2_ROOT_STAGE_REVIEW.json'\nJSON_LIMIT = 16384\n", "C1_FILE = 'C2_V2_ROOT_C1_REVIEW.json'\nC4_FILE = 'C2_V2_ROOT_C4_REVIEW.json'\nC2_ENTRY_FILE = 'C2_V2_ROOT_ENTRY_REVIEW.json'\nSTAGE_FILE = 'C2_V2_ROOT_STAGE_REVIEW.json'\nJSON_LIMIT = 16384\n")
        text = replace_once(text, "    'property_id', 'same_unpromoted_uuid_verified', 'restored_editor_step',\n    'restored_frame_sha256'})\nSTAGE_KEYS = frozenset({'executor_cursor', 'actual_frame_file', 'kind', 'context', 'privacy_checked',\n    'manual_review_completed', 'fixture_key', 'fixture_tag', 'exact_fixture_title',\n", "    'property_id', 'same_unpromoted_uuid_verified', 'restored_editor_step',\n    'restored_frame_sha256'})\nC2_ENTRY_KEYS = frozenset({'kind', 'phase', 'privacy_checked', 'manual_review_completed',\n    'fixture_key', 'fixture_tag', 'restored_title', 'monthly_rent_still_blank',\n    'property_id', 'same_unpromoted_uuid_verified', 'restored_editor_step',\n    'restored_frame_sha256', 'restored_photo_frame_sha256', 'entry_mode',\n    'current_fixture_visually_verified', 'review_completed_utc'})\nSTAGE_KEYS = frozenset({'executor_cursor', 'actual_frame_file', 'kind', 'context', 'privacy_checked',\n    'manual_review_completed', 'fixture_key', 'fixture_tag', 'exact_fixture_title',\n")
        text = replace_once(text, "    'old_support_workspace_visible', 'evidence_kind', 'editor_chain',\n    'same_serialized_editor_chain_reviewed', 'original_fixture_receipt_reviewed',\n    'bound_c4_title_frame', 'photo_visually_unchanged', 'actual_safe_spec_photo_reviewed',\n    'semantic_preview', 'policy_was_visually_reviewed', 'safe_surface_frames',\n    'regular_cycle', 'nonimage_role_witness', 'same_serialized_support_case_chain_reviewed',\n", "    'old_support_workspace_visible', 'evidence_kind', 'editor_chain',\n    'same_serialized_editor_chain_reviewed', 'original_fixture_receipt_reviewed',\n    'bound_c4_title_frame', 'bound_fixture_title_frame', 'photo_visually_unchanged', 'actual_safe_spec_photo_reviewed',\n    'semantic_preview', 'policy_was_visually_reviewed', 'safe_surface_frames',\n    'regular_cycle', 'nonimage_role_witness', 'same_serialized_support_case_chain_reviewed',\n")
        text = replace_once(text, 'def _read(probe, filename, allowed):\n    """Read only one fixed non-symlink0600 bounded Root review, no secret path."""\n    need(filename in {C1_FILE, C4_FILE, STAGE_FILE}, \'review_filename_not_allowlisted\')\n    need(type(probe.private_values) is set, \'parent_redaction_set_required\')\n    path = Path(probe.out) / filename\n', 'def _read(probe, filename, allowed):\n    """Read only one fixed non-symlink0600 bounded Root review, no secret path."""\n    need(filename in {C1_FILE, C4_FILE, C2_ENTRY_FILE, STAGE_FILE}, \'review_filename_not_allowlisted\')\n    need(type(probe.private_values) is set, \'parent_redaction_set_required\')\n    path = Path(probe.out) / filename\n')
        text = replace_once(text, "\ndef _bind_frame(probe, filename, wanted):\n    # Only the already recorded safe restored-title images are read here.\n    need(filename in {'C1-restored-title.png', 'C1-c4-restored-final-title.png'},\n         'accepted_review_frame_not_allowlisted')\n    receipts = [row for row in probe.report.get('frames', []) if row.get('file') == filename]\n", "\ndef _bind_frame(probe, filename, wanted):\n    # Only already recorded safe restored-title/photo images are read here.\n    need(filename in {'C1-restored-title.png', 'C1-restored-complete-photo.png',\n                      'C1-c4-restored-final-title.png'},\n         'accepted_review_frame_not_allowlisted')\n    receipts = [row for row in probe.report.get('frames', []) if row.get('file') == filename]\n")
        text = replace_once(text, "\n\ndef _configure(probe, module):\n    need(not hasattr(probe, '_root_c2_executor'), 'existing_v1_executor_requires_root_reconciliation')\n    c1, _ = _read(probe, C1_FILE, C1_KEYS)\n", '\n\ndef _configure_standard(probe, module):\n    """Current C1 fixture enters C2 directly; no C4 state or acceptance exists."""\n    need(not hasattr(probe, \'_root_c2_executor\'), \'existing_v1_executor_requires_root_reconciliation\')\n    need(\'local_c4_executor\' not in probe.report, \'c2_only_current_c4_state_refused\')\n    c1, _ = _read(probe, C1_FILE, C1_KEYS)\n    entry, _ = _read(probe, C2_ENTRY_FILE, C2_ENTRY_KEYS)\n    need(set(c1) == C1_KEYS and set(entry) == C2_ENTRY_KEYS and\n         c1.get(\'phase\') == \'C1\' and entry.get(\'phase\') == \'C2\',\n         \'current_c1_c2_entry_review_phase_required\')\n    need(c1.get(\'manual_review_completed\') is True and c1.get(\'c1_accepted\') is True and\n         c1.get(\'privacy_checked\') is True and c1.get(\'monthly_rent_still_blank\') is True and\n         entry.get(\'manual_review_completed\') is True and entry.get(\'privacy_checked\') is True and\n         entry.get(\'monthly_rent_still_blank\') is True and entry.get(\'property_id\') is None and\n         entry.get(\'same_unpromoted_uuid_verified\') is True and\n         entry.get(\'current_fixture_visually_verified\') is True and\n         entry.get(\'entry_mode\') == \'standard_editor\' and\n         type(entry.get(\'restored_editor_step\')) is int and entry[\'restored_editor_step\'] == 0,\n         \'actual_current_c1_c2_entry_review_required\')\n    state = getattr(getattr(probe, \'fixture_api\', None), \'state\', None)\n    need(isinstance(state, dict) and state.get(\'actor_id\') == 28 and\n         state.get(\'key\') == probe.report.get(\'fixture_key\') and\n         state.get(\'tag\') == probe.report.get(\'fixture_tag\') and\n         c1.get(\'fixture_key\') == state.get(\'key\') == entry.get(\'fixture_key\') and\n         c1.get(\'fixture_tag\') == state.get(\'tag\') == entry.get(\'fixture_tag\') and\n         c1.get(\'native_title\') == probe.title == entry.get(\'restored_title\'),\n         \'original_bootstrap_state_and_reviews_required\')\n    required_cases = {\'C1-photo-save\', \'C1-force-stop-restore\'}\n    actual_cases = [row for row in probe.report.get(\'cases\', []) if row.get(\'id\') in required_cases]\n    checks = probe.report.get(\'c1_monthly_rent_blank_checks\')\n    need(len(actual_cases) == 2 and {row.get(\'id\') for row in actual_cases} == required_cases and\n         all(row.get(\'status\') == \'PASS\' for row in actual_cases) and\n         type(checks) is dict and set(checks) == {\'before_save\', \'after_reopen\'} and\n         checks[\'before_save\'] is True and checks[\'after_reopen\'] is True and\n         probe.report.get(\'held_after_c1_restore_for_root_review\') is True and\n         probe.authenticated is True and getattr(probe, \'recorder\', None) is None and\n         not getattr(probe, \'_host_stop_unconfirmed\', False),\n         \'actual_current_c1_restored_hold_required\')\n    need(c1[\'restored_frame_sha256\'] == entry[\'restored_frame_sha256\'],\n         \'current_c1_entry_title_frame_mismatch\')\n    _bind_frame(probe, \'C1-restored-title.png\', entry[\'restored_frame_sha256\'])\n    _bind_frame(probe, \'C1-restored-complete-photo.png\', entry[\'restored_photo_frame_sha256\'])\n    access = getattr(probe, \'access\', None)\n    need(isinstance(access, dict) and isinstance(access.get(\'phones\'), dict) and\n         {\'broker\', \'support\', \'regular\'} <= set(access[\'phones\']),\n         \'all_three_validated_roles_must_already_be_in_parent_memory\')\n    need(callable(getattr(probe.fixture_api, \'_call\', None)), \'normal_parent_api_adapter_required\')\n    return module.configure_c2(probe, state, c1, None, entry_review=entry,\n        role_loader=lambda: probe.access,\n        request=lambda method, path, body, token:\n            probe.fixture_api._call(method, path, body=body, token=token))\n\n\ndef _configure(probe, module):\n    if getattr(probe, \'_root_c2_entry_mode\', None) == \'c2_only\':\n        return _configure_standard(probe, module)\n    need(not hasattr(probe, \'_root_c2_executor\'), \'existing_v1_executor_requires_root_reconciliation\')\n    c1, _ = _read(probe, C1_FILE, C1_KEYS)\n')
        text = replace_once(text, "                              if action_text is not None and action_text in module.policy.names(row)]}\n    if stage == 'review_photo_before_save':\n        bindings['serialized_identity_binding'] = {\n            'fixture_key': executor.key, 'fixture_tag': executor.tag,\n            'editor_chain': executor.editor_chain,\n            'prior_c4_tagged_title_frame': {'file': 'C1-c4-restored-final-title.png',\n                                           'sha256': executor.c4['restored_frame_sha256']},\n            'fixture_title_visible_in_this_spec_frame': False}\n    if stage == 'return_open':\n        need(executor._case_header() == executor.case_header_binding,\n", "                              if action_text is not None and action_text in module.policy.names(row)]}\n    if stage == 'review_photo_before_save':\n        identity = {'fixture_key': executor.key, 'fixture_tag': executor.tag,\n                    'editor_chain': executor.editor_chain,\n                    'fixture_title_visible_in_this_spec_frame': False}\n        if getattr(executor, 'entry_mode', None) == 'standard_editor':\n            identity['prior_fixture_tagged_title_frame'] = dict(executor.fixture_title_frame)\n        else:\n            identity['prior_c4_tagged_title_frame'] = {'file': 'C1-c4-restored-final-title.png',\n                                                     'sha256': executor.c4['restored_frame_sha256']}\n        bindings['serialized_identity_binding'] = identity\n    if stage == 'return_open':\n        need(executor._case_header() == executor.case_header_binding,\n")
    return text


def c2_preview_diagnostic_transform(name, text):
    """Record fixed preview outcomes without retaining raw values or changing guards."""
    if name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
        text = replace_once(text, '        names = _names(p.nodes())  # Ephemeral only; no tree/root/node hashes or raw text retained.\n', "        names = _names(p.nodes())  # Ephemeral only; no tree/root/node hashes or raw text retained.\n        def shape(value, expected):\n            # Fixed categories only; these observations never broaden acceptance.\n            if value == expected:\n                return 'EXPECTED'\n            if not value:\n                return 'EMPTY'\n            if re.fullmatch(r'0[.٫]0{1,2}', value):\n                return 'ZERO_DECIMAL'\n            if (re.fullmatch(r'[1-9][0-9]{0,2}(?:[,٬][0-9]{3})+', value) and\n                    value.replace(',', '').replace('٬', '') == expected):\n                return 'GROUPED_EXPECTED'\n            return 'OTHER'\n        p.report['c2_v2_rent_sai_readback_diagnostic'] = {\n            'stage': STAGES[self.cursor], 'fixture_key': self.key,\n            'fixture_tag': self.tag, 'editor_chain': self.editor_chain,\n            'rent_matches_expected': rent == self.monthly_rent,\n            'sai_rate_is_zero': rate == '0',\n            'auth_surface_absent': not bool(names & roles.AUTH_LABELS),\n            'accept_reject_absent': not bool(names & {'قبول', 'رفض'}),\n            'rent_shape': shape(rent, self.monthly_rent), 'rate_shape': shape(rate, '0')}\n")
    return text


def transform(name, text):
    if name in {'ROOT_C4_EXECUTOR/phase_extensions.py', 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py'}:
        alphabet = ''.join(str(value) for value in range(10)) * 2
        text = replace_once(text, repr(alphabet),
                            "(''.join(str(value) for value in range(10)) * 2)")
    if name == 'ROOT_C4_EXECUTOR/phase_extensions.py':
        text = replace_once(text, 'import uuid\n',
                            'import uuid\nfrom ci_remote_evidence import normalize_c4_review, reject_duplicate_pairs\n')
        text = replace_once(text, '        data = json.loads(path.read_text())',
            "        data = normalize_c4_review(json.loads(path.read_text(), object_pairs_hook=reject_duplicate_pairs),\n"
            "            expected_cursor=cursor, expected_frames=frames, actual_video=state.get('restore_video'))")
        text = replace_once(text, "state['helper_or_recorder_release_unconfirmed'] = True",
                            "state['admission_or_recorder_stop_unconfirmed'] = True")
        text = replace_once(text, "data.get('copy_has_only_explicit_brief_facts') is True",
                            "data.get('copy_has_only_supplied_facts') is True")
        text = replace_once(text, "    selected = data.get('selected_fields')",
            "    existing = data.get('verified_existing_draft_copy_facts')\n"
            "    need(type(existing) is dict and set(existing) <= {'address','governorate','district','street','city'}\n"
            "         and all(type(v) is str and 0 < len(v) <= 240 for v in existing.values()),\n"
            "         'c4_verified_existing_copy_facts_required')\n"
            "    selected = data.get('selected_fields')")
        text = replace_once(text, "    probe.set('صف العقار', BRIEF)\n    probe.tap('جهّز الإعلان')",
            "    probe.set('صف العقار', BRIEF)\n"
            "    probe.require_value('صف العقار', BRIEF)\n"
            "    state['prepared_brief_scene'] = ai_scene(probe)\n"
            "    # End before the network request. Request/response and actual proposal\n"
            "    # capture receive a separate original120s grant, without refreshing this one.\n"
            "    return finish(probe, state, 'REQUEST')\n\n\n"
            "def prepared_brief_context(probe, state):\n"
            "    ensure_session(probe)\n"
            "    observed = ai_scene(probe)\n"
            "    need(observed == state.get('prepared_brief_scene'), 'c4_prepared_brief_scene_changed')\n"
            "    probe.require_value('صف العقار', BRIEF)\n"
            "    return observed\n\n\n"
            "def request_prepared(probe, state):\n"
            "    reserve(probe, state, 'prepare_request')\n"
            "    prepared_brief_context(probe, state)\n"
            "    probe.tap('جهّز الإعلان')")
        text = replace_once(text,
            "            return prepare(probe, state)\n        if cursor in {'AI_REVIEW', 'APPLY_REVIEW', 'RESTORE_REVIEW'}:",
            "            return prepare(probe, state)\n        if cursor == 'REQUEST':\n"
            "            return request_prepared(probe, state)\n"
            "        if cursor in {'AI_REVIEW', 'APPLY_REVIEW', 'RESTORE_REVIEW'}:")
        text = replace_once(text, '    # End before the network request. Request/response and actual proposal\n    # capture receive a separate original120s grant, without refreshing this one.', '    # End before the network request; each subsequent segment uses its own\n    # fresh signed authority without refreshing an existing grant.')
        text = replace_once(text, '    probe.wait(APPLY, seconds=120)\n    # Notice must be observed literally on the real native sheet.', "    probe.wait(APPLY, seconds=120)\n    # Preserve the actual response before any scrolling. This diagnostic is\n    # neither an AI-source assertion nor a visual acceptance decision.\n    state['response_ready_frames'] = ai_capture(probe, 'C1-c4-response-ready')\n    state['response_ready_scene'] = ai_scene(probe)\n    return finish(probe, state, 'RESPONSE_READY')\n\n\ndef seek_ai_notice(probe, state):\n    # Short overlapping physical swipes avoid skipping the small notice with\n    # full flings. Inspect the literal fallback too; never relabel it as AI.\n    directions = ('backward',) * 4 + ('forward',) * 8\n    diagnostic = {'observations': 0, 'short_scrolls_completed': 0,\n                  'ai_notice_seen': False, 'literal_fallback_seen': False}\n    state['notice_seek'] = diagnostic\n    for index in range(len(directions) + 1):\n        rows = [row for row in safe_rows(probe) if row.get('visible') is True]\n        diagnostic['observations'] += 1\n        diagnostic['ai_notice_seen'] = any(AI_NOTICE in names(row) for row in rows)\n        diagnostic['literal_fallback_seen'] = any(FALLBACK_NOTICE in names(row) for row in rows)\n        save(probe)\n        need(not diagnostic['literal_fallback_seen'], 'c4_literal_fallback_observed_no_ai_acceptance')\n        if diagnostic['ai_notice_seen']:\n            return\n        if index < len(directions):\n            probe.scroll(directions[index], short=True)\n            diagnostic['short_scrolls_completed'] += 1\n            save(probe)\n    need(False, 'c4_actual_ai_notice_not_observed_after_bounded_short_seek')\n\n\ndef collect_response(probe, state):\n    reserve(probe, state, 'collect_response')\n    ensure_session(probe)\n    need(ai_scene(probe) == state.get('response_ready_scene'), 'c4_response_ready_scene_changed')\n    # Notice must be observed literally on the real native sheet.")
        text = replace_once(text, '    probe.seek(AI_NOTICE)', '    seek_ai_notice(probe, state)')
        text = replace_once(text, "        if cursor == 'REQUEST':\n            return request_prepared(probe, state)\n", "        if cursor == 'REQUEST':\n            return request_prepared(probe, state)\n        if cursor == 'RESPONSE_READY':\n            return collect_response(probe, state)\n")
        text = replace_once(text,
            "    probe.set('عنوان الإعلان', state['title'])\n"
            "    probe.require_value('عنوان الإعلان', state['title'])\n",
            "    title_changed = probe.field('عنوان الإعلان').get('text') != state['title']\n"
            "    if title_changed:\n"
            "        probe.set('عنوان الإعلان', state['title'])\n"
            "    probe.require_value('عنوان الإعلان', state['title'])\n"
            "    if title_changed:\n"
            "        # Observe the fixed footer after IME/layout settling; never replay input.\n"
            "        probe.wait(APPLY, seconds=5)\n")
    elif name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
        text = replace_once(text, 'import time\n', 'import time\nfrom ci_remote_evidence import fresh_remote_review\n')
        text = replace_once(text,
            "            type(review.get('reviewed_monotonic')) in (int, float) and\n"
            "            0 <= time.monotonic() - review['reviewed_monotonic'] <= 120)",
            '            fresh_remote_review(review))')
        text = replace_once(text,
            "                 type(record.get('reviewed_monotonic')) in (int, float) and\n"
            "                 0 <= time.monotonic() - record['reviewed_monotonic'] <= 120,",
            '                 fresh_remote_review(record),')
    elif name == 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py':
        text = replace_once(text, 'import uuid\n', 'import uuid\nfrom ci_remote_evidence import fresh_remote_review\n')
        text = replace_once(text, '*, native_role, auth_uncertain, now=None):',
                            '*, native_role, auth_uncertain, now_utc=None):')
        text = replace_once(text,
            "    observed = review.get('reviewed_monotonic')\n"
            '    now = time.monotonic() if now is None else now\n'
            '    need(type(observed) in (int, float) and 0 <= now - observed <= 120,\n',
            '    need(fresh_remote_review(review, now_utc=now_utc),\n')
    elif name == 'C2_SOURCE_PROPOSAL/c2_native_roles.py':
        text = replace_once(text, 'import time\n', 'import time\nfrom ci_remote_evidence import fresh_remote_review\n')
        # V2 does not call the unbuilt atomic scoped-card function, but keeping
        # its unused selector on the same UTC schema avoids a legacy time path.
        text = replace_once(text,
            "    reviewed_at = visual_review.get('reviewed_monotonic')\n"
            '    need(type(reviewed_at) in (int, float) and\n'
            '         0 <= time.monotonic() - reviewed_at <= 120,\n',
            '    need(fresh_remote_review(visual_review),\n')
        # AuthController clears the account scope; AppShell resets index0 to
        # GuestMarketplace. Regular/guest share footer labels, so the footer
        # alone cannot prove this actual Home transition.
        text = replace_once(text, "\nAUTH_LABELS = frozenset(",
            "\nGUEST_HOME_ANCHORS = frozenset({'ابحث عن عقار أو منطقة…', 'ماذا تبحث عنه؟'})\n"
            "GUEST_HOME_NAV = frozenset({'العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'})\n"
            "\nAUTH_LABELS = frozenset(")
        text = replace_once(text, '\ndef _safe_role_failure(error):',
            "\ndef _visible_app_names(rows):\n"
            "    return _visible_names([row for row in rows if row.get('package') == APP\n"
            "                           and row.get('visible') is True])\n\n"
            "\ndef _safe_role_failure(error):")
        text = replace_once(text,
            "'expected_native_role_not_observed', 'native_guest_logout_state_not_observed'}",
            "'expected_native_role_not_observed', 'native_guest_logout_state_not_observed',\n"
            "            'native_guest_marketplace_not_observed', 'retained_broker_home_not_observed',\n"
            "            'support_queue_before_logout_required', 'support_shell_before_logout_required'}")
        text = replace_once(text,
            "               'server_token_revocation_verified': False}\n    try:\n        probe.tap('حسابي', seek=False)",
            "               'server_token_revocation_verified': False}\n    try:\n"
            "        if role == 'broker':\n"
            "            # MyListings is a standalone route without the Account footer.\n"
            "            # Relaunch its already retained session, as in C1 logout; never\n"
            "            # reset storage, guess Back navigation, or enter credentials.\n"
            "            if probe.adapter is not None:\n"
            "                probe.stop_session('C2_broker_logout_retained_home')\n"
            "            probe.adb('shell', 'am', 'force-stop', APP)\n"
            "            probe.startup()\n"
            "            names = _visible_app_names(probe.nodes())\n"
            "            need(ROLE_NAV['broker'] <= names and not names & AUTH_LABELS\n"
            "                 and 'تسجيل الدخول أو إنشاء حساب' not in names,\n"
            "                 'retained_broker_home_not_observed')\n"
            "            receipt['retained_broker_home_observed'] = True\n"
            "        elif role == 'support':\n"
            "            names = _visible_app_names(probe.nodes())\n"
            "            if not ROLE_NAV['support'] <= names:\n"
            "                # The task opens this queue with context.push; its standard\n"
            "                # AppBar Back is Arabic Material's observed named control.\n"
            "                need({'تحقيق الإعلانات', 'طلبات التحقيق', 'رجوع'} <= names\n"
            "                     and not names & AUTH_LABELS,\n"
            "                     'support_queue_before_logout_required')\n"
            "                probe.tap('رجوع', seek=False)\n"
            "                probe.wait('لوحة الدعم', seconds=15)\n"
            "                names = _visible_app_names(probe.nodes())\n"
            "            need(ROLE_NAV['support'] <= names and not names & AUTH_LABELS\n"
            "                 and 'تسجيل الدخول أو إنشاء حساب' not in names,\n"
            "                 'support_shell_before_logout_required')\n"
            "            receipt['support_shell_before_logout_observed'] = True\n"
            "        probe.tap('حسابي', seek=False)")
        text = replace_once(text,
            "        probe.wait('تسجيل الدخول أو إنشاء حساب', seconds=90)\n"
            "        names = _visible_names(probe.nodes())\n",
            "        deadline = time.monotonic() + 90\n"
            "        while time.monotonic() < deadline:\n"
            "            names = _visible_app_names(probe.nodes())\n"
            "            if (GUEST_HOME_NAV <= names and names & GUEST_HOME_ANCHORS\n"
            "                    and 'تسجيل الخروج' not in names and not names & AUTH_LABELS\n"
            "                    and not names & {'عملي', 'العملاء', 'لوحة الدعم', 'الوارد', 'مهامي'}):\n"
            "                break\n"
            "            time.sleep(.7)\n"
            "        else:\n"
            "            raise RouteBlocked('native_guest_marketplace_not_observed')\n"
            "        # Exactly one post-logout Account tap, after actual Home.\n"
            "        probe.tap('حسابي', seek=False)\n"
            "        probe.wait('تسجيل الدخول أو إنشاء حساب', seconds=45)\n"
            "        names = _visible_app_names(probe.nodes())\n")
        text = replace_once(text,
            "receipt.update(status='PASS_WITHIN_LOGOUT_UI_SCOPE', guest_gate_observed=True)",
            "receipt.update(status='PASS_WITHIN_LOGOUT_UI_SCOPE', guest_gate_observed=True,\n"
            "                       guest_marketplace_home_observed=True, post_logout_account_tap_delivered=True)")
    elif name == 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py':
        text = replace_once(text, 'import tempfile\n', 'import tempfile\nfrom ci_remote_evidence import fresh_remote_review\n')
        text = replace_once(text, "BASE = Path('/workspace/scratch/e1739659bfa7/native-fixture')",
                            'BASE = Path(__file__).resolve().parents[1]')
        text = replace_once(text, "'frame_sha256', 'reviewed_monotonic', 'root_witness'",
                            "'frame_sha256', 'review_completed_utc', 'root_witness'")
        text = replace_once(text, '\n\nclass Hold(RuntimeError):',
            "\nC1_KEYS = C1_KEYS | {'review_completed_utc'}\n"
            "C4_KEYS = C4_KEYS | {'review_completed_utc'}\n\n\nclass Hold(RuntimeError):")
        text = replace_once(text,
            "    need(isinstance(data, dict) and set(data) <= allowed and\n",
            "    need(fresh_remote_review(data), 'root_review_utc_expired')\n"
            "    need(isinstance(data, dict) and set(data) <= allowed and\n")
        text = replace_once(text, "            receipt['helper_released_at_boundary'] = True",
            "            receipt['oneshot_admission_closed_at_boundary'] = True\n"
            "            receipt['persistent_helper_release_claimed'] = False\n"
            "            receipt['oneshot_admission'] = probe.admission_metrics")
        text = text.replace('_root_extension_dispatch_v2_helper_failed', '_root_extension_dispatch_v2_admission_failed')
        text = replace_once(text, 'previous_helper_release_failure_requires_root_review',
                            'previous_admission_close_failure_requires_root_review')
        text = replace_once(text, 'HELD_HELPER_RELEASE_UNCONFIRMED', 'HELD_ADMISSION_CLOSE_UNCONFIRMED')
        text = replace_once(text, 'reconciles this helper lease;', 'disposes this uncertain runtime;')
        text = replace_once(text, "        need(phase in ('C4', 'C2'), 'extension_phase_refused')",
            "        need(phase in ('C4', 'C2'), 'extension_phase_refused')\n"
            "        need(probe.require_phase_scope(phase) is True, 'active_root_phase_grant_required')")
    text = support_case_review_transform(name, text)
    text = c2_diagnostic_transform(name, text)
    text = c2_only_entry_transform(name, text)
    text = c2_preview_diagnostic_transform(name, text)
    if name != 'promoted_cleanup.py' and 'reviewed_monotonic' in text:
        raise RuntimeError('legacy_review_clock_remains')
    return text


def build(source_root, capture_source, destination):
    source_root, capture_source, destination = map(Path, (source_root, capture_source, destination))
    if destination.exists():
        raise RuntimeError('fresh_variant_destination_required')
    outputs, originals = {}, {}
    for name, wanted in PINS.items():
        path = source_root / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('pinned_variant_source_unavailable')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != wanted:
            raise RuntimeError('pinned_variant_source_mismatch')
        originals[name] = data
        outputs[name] = transform(name, data.decode()).encode()
    capture = capture_source.read_bytes()
    if capture_source.is_symlink() or hashlib.sha256(capture).hexdigest() != CAPTURE_PIN:
        raise RuntimeError('pinned_capture_source_mismatch')
    outputs['runtime/host_console_capture.py'] = capture
    outputs['ci_remote_evidence.py'] = Path(__file__).with_name('ci_remote_evidence.py').read_bytes()
    destination.mkdir(mode=0o700, parents=True)
    manifest = {}
    for name, data in outputs.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
                          'original_sha256': PINS.get(name, CAPTURE_PIN if name.startswith('runtime/') else None)}
        if name in {'ROOT_C4_EXECUTOR/phase_extensions.py', 'LOCAL_REMAINING_PROPOSAL/local_stage_policy.py'}:
            manifest[name]['delta'] = 'equivalent_generated_digit_translation_alphabet'
        if name == 'ROOT_C4_EXECUTOR/phase_extensions.py':
            manifest[name]['delta'] += '; separate_exact_brief_REQUEST_checkpoint_before_AI_request; copy_grounded_in_message_and_verified_same_draft_facts; actual_response_snapshot_boundary_before_bounded_short_notice_seek; preserve_exact_reviewed_title_without_redundant_input; observe_footer_after_changed_title_input'
        if name == 'C2_SOURCE_PROPOSAL/c2_native_roles.py':
            manifest[name]['previous_utc_variant_sha256'] = PREVIOUS_ROLES_PIN
            manifest[name]['delta'] = 'one_logout_observed_guest_home_then_one_account_guest_gate; broker_retained_home_and_support_named_back_before_normal_logout'
        if name == 'ROOT_C2_EXECUTOR_V2/phase_extensions.py':
            manifest[name]['delta'] = 'serialized_support_case_title_to_action_and_truthful_return_queue; fixed_nonimage_rent_sai_operation_diagnostics; fixed_preview_guard_booleans_and_value_shapes; actual_current_C1_native_entry_without_current_C4_state; verified_standard_editor_and_normal_full_save'
        if name == 'ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py':
            manifest[name]['delta'] = 'separate_case_title_action_and_queue_evidence_bindings; actual_current_C1_title_photo_blank_rent_review_for_C2_entry; distinct_current_fixture_standard_editor_identity'
    # Check the inputs again so this preparation cannot quietly alter originals.
    for name, data in originals.items():
        if (source_root / name).read_bytes() != data:
            raise RuntimeError('original_variant_source_changed')
    (destination / 'VARIANT_MANIFEST.json').write_text(json.dumps({
        'scope': 'Offline remote-UTC plus guest-Home logout variant; no native acceptance',
        'source_files_unchanged': True, 'manifest': manifest}, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', required=True)
    parser.add_argument('--capture-source', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source_root, args.capture_source, args.output), indent=2))
