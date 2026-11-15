"""Advance local control state only for the expected run and a fresh checkpoint."""


def advance_checkpoint(state, observation, *, run_id, source_sha):
    if str(observation.get('run_id')) != str(run_id) or observation.get('source_sha') != source_sha:
        raise ValueError('foreign_checkpoint_refused')
    sequence = observation.get('seq')
    if type(sequence) is not int or sequence < 0:
        raise ValueError('checkpoint_sequence_invalid')
    same_run = str(state.get('activeNativeRun')) == str(run_id)
    current = state.get('current_seq', -1) if same_run else -1
    if sequence < current:
        raise ValueError('checkpoint_rollback_refused')
    if sequence == current and state.get('current_challenge') != observation.get('challenge'):
        raise ValueError('checkpoint_challenge_conflict')
    return {**state, 'activeNativeRun': int(run_id), 'executionSource': source_sha,
            'current_seq': sequence, 'current_challenge': observation['challenge'],
            'current_actor': observation.get('actor'), 'apk': observation['apk']}
