"""In-memory input authority issued only by the reviewed owner, never a dict."""
from datetime import datetime, timedelta, timezone
import hashlib
import re
import time

import review_protocol as protocol

_CAPABILITY = object()
CATEGORIES = frozenset({'tap', 'text', 'scroll', 'back', 'app_start', 'app_stop',
    'os_picker', 'media_write', 'recorder_start', 'recorder_stop'})


class GrantRefused(RuntimeError):
    pass


def require(value, code):
    if not value:
        raise GrantRefused(code)


def utc(value):
    require(type(value) is str and re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z', value), 'review_utc_format_invalid')
    try:
        return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        raise GrantRefused('review_utc_value_invalid') from None


class VerifiedGrant:
    """Issued/active only inside the already-reserved protocol dispatch callback."""
    def __init__(self, capability, *, validated, context, issued_utc, received_utc,
                 received_monotonic, work_deadline, utc_clock, monotonic_clock):
        require(capability is _CAPABILITY and isinstance(validated, protocol.Validated)
                and isinstance(context, protocol.Context), 'verified_owner_factory_required')
        review = validated.review
        reviewed = utc(review.get('review_completed_utc'))
        issued = utc(issued_utc)
        require(received_utc.tzinfo is not None and received_utc.utcoffset() == timedelta(0), 'utc_clock_required')
        require(reviewed <= received_utc + timedelta(seconds=5)
                and reviewed <= issued + timedelta(seconds=5)
                and 0 <= (received_utc - reviewed).total_seconds() + 5 <= 125,
                'actual_review_time_not_fresh')
        require(validated.op == 'advance' and validated.seq == context.seq,
                'advance_grant_required')
        require(validated.context_sha == hashlib.sha256(protocol.canonical(context.fields())).hexdigest(),
                'verified_grant_context_mismatch')
        self._context, self._command_sha = context, validated.command_sha
        self._reviewed, self._issued, self._expires = reviewed, issued, validated.expires_utc
        self._mono, self._utc = monotonic_clock, utc_clock
        self._deadline = min(work_deadline, received_monotonic
                             + (self._expires - received_utc).total_seconds())
        self._active = True

    @property
    def context(self): return self._context

    @property
    def authority_kind(self): return 'ROOT_VERIFIED'

    @property
    def command_sha(self): return self._command_sha

    @property
    def review_completed_utc(self): return self._reviewed

    @property
    def issued_utc(self): return self._issued

    @property
    def expires_utc(self): return self._expires

    @property
    def monotonic_deadline(self): return self._deadline

    def revoke(self): self._active = False

    def require_current(self, context, minimum_remaining_seconds=0):
        require(self._active and type(context) is protocol.Context and context == self._context,
                'active_context_grant_required')
        require(type(minimum_remaining_seconds) in (int, float)
                and 0 <= minimum_remaining_seconds <= 120, 'mutation_budget_invalid')
        current = self._utc()
        require(isinstance(current, datetime) and current.tzinfo is not None
                and current.utcoffset() == timedelta(0), 'utc_clock_required')
        require(self._deadline - self._mono() >= minimum_remaining_seconds
                and current + timedelta(seconds=minimum_remaining_seconds) <= self._expires,
                'signed_input_deadline_expired')
        return True

    def require_input(self, context, mutation_category, minimum_remaining_seconds=0):
        require(type(mutation_category) is str and mutation_category in CATEGORIES,
                'fixed_mutation_category_required')
        return self.require_current(context, minimum_remaining_seconds)


class SourcePlanLease:
    """Separate initial C1 source-plan authority. Never a Root visual review."""
    def __init__(self, capability, *, context, start_monotonic, work_deadline, monotonic_clock):
        require(capability is _CAPABILITY and isinstance(context, protocol.Context)
                and context.phase == 'C1' and context.cursor == 'INITIAL_C1',
                'initial_source_plan_factory_required')
        self._context, self._mono = context, monotonic_clock
        self._deadline = min(work_deadline, start_monotonic + 600)
        self._active = True

    @property
    def context(self): return self._context

    @property
    def authority_kind(self): return 'SOURCE_PLAN_ONLY'

    @property
    def monotonic_deadline(self): return self._deadline

    def revoke(self): self._active = False

    def require_current(self, context, minimum_remaining_seconds=0):
        require(self._active and type(context) is protocol.Context and context == self._context,
                'active_source_plan_required')
        require(type(minimum_remaining_seconds) in (int, float)
                and 0 <= minimum_remaining_seconds <= 120, 'mutation_budget_invalid')
        require(self._deadline - self._mono() >= minimum_remaining_seconds,
                'initial_source_plan_expired')
        return True

    def require_input(self, context, mutation_category, minimum_remaining_seconds=0):
        require(type(mutation_category) is str and mutation_category in CATEGORIES,
                'fixed_mutation_category_required')
        return self.require_current(context, minimum_remaining_seconds)


def issue_verified(*, validated, context, issued_utc, received_utc, received_monotonic,
                   work_deadline, utc_clock=lambda: datetime.now(timezone.utc),
                   monotonic_clock=time.monotonic):
    """Owner call site must be inside protocol.receive's reserved dispatch."""
    return VerifiedGrant(_CAPABILITY, validated=validated, context=context,
        issued_utc=issued_utc, received_utc=received_utc,
        received_monotonic=received_monotonic, work_deadline=work_deadline,
        utc_clock=utc_clock, monotonic_clock=monotonic_clock)


def issue_initial(*, context, start_monotonic, work_deadline,
                  monotonic_clock=time.monotonic):
    """One source-only lease after VM boot, before native setup/public feed.

    The same lease spans the actual public-feed proof, API title bootstrap,
    fixture-checkpoint ACK, and initial C1 native routine. Never renew it.
    """
    return SourcePlanLease(_CAPABILITY, context=context, start_monotonic=start_monotonic,
                          work_deadline=work_deadline, monotonic_clock=monotonic_clock)


class CleanupLease:
    """Only the fixed owner cleanup body; never a phase-extension authority."""
    def __init__(self, capability, *, context, cleanup_deadline, uncertain,
                 utc_clock, monotonic_clock):
        require(capability is _CAPABILITY and isinstance(context, protocol.Context)
                and context.phase == 'C5' and context.cursor == 'OWNER_CLEANUP',
                'owner_cleanup_factory_required')
        self._context, self._mono, self._utc = context, monotonic_clock, utc_clock
        self._deadline, self._uncertain = cleanup_deadline, uncertain is True
        remaining = max(0, min(120, cleanup_deadline - self._mono()))
        self._expires = (self._utc() + timedelta(seconds=remaining)).replace(microsecond=0)
        self._active = True

    @property
    def context(self): return self._context

    @property
    def authority_kind(self): return 'OWNER_CLEANUP'

    @property
    def expires_utc(self): return self._expires

    @property
    def monotonic_deadline(self): return self._deadline

    def revoke(self): self._active = False

    def require_input(self, context, mutation_category, minimum_remaining_seconds=0):
        require(self._active and type(context) is protocol.Context and context == self._context,
                'active_cleanup_scope_required')
        safe_stops = {'app_stop', 'recorder_stop'}
        allowed = safe_stops if self._uncertain else safe_stops | {'app_start', 'back', 'tap', 'scroll'}
        require(type(mutation_category) is str and mutation_category in allowed,
                'cleanup_mutation_not_authorized')
        require(type(minimum_remaining_seconds) in (int, float)
                and 0 <= minimum_remaining_seconds <= 120, 'mutation_budget_invalid')
        require(self._deadline - self._mono() >= minimum_remaining_seconds,
                'owner_cleanup_reserve_expired')
        if mutation_category not in safe_stops:
            require(self._utc() <= self._expires, 'owner_cleanup_ui_deadline_expired')
        return True


def issue_cleanup(*, context, cleanup_deadline, uncertain,
                  utc_clock=lambda: datetime.now(timezone.utc), monotonic_clock=time.monotonic):
    return CleanupLease(_CAPABILITY, context=context, cleanup_deadline=cleanup_deadline,
                        uncertain=uncertain, utc_clock=utc_clock, monotonic_clock=monotonic_clock)
