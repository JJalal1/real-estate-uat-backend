# Offline one-shot admission foundation

This directory contains no native runner, authentication, API client, capture
code or acceptance result. It does not modify the current GitHub collector.

`OneShotInstrumentAdapter` binds an externally supplied **synchronous checked**
instrumentation method, such as the existing `NativeAccount.instrument` method.
That method must wait for `am instrument -w`, check the instrumentation operation
and success receipt, and check `INSTRUMENTATION_CODE` before it returns. It must
never retry an uncertain operation.

```python
gate = OneShotAdmission()  # Keep this object for the whole owned runtime.
adapter = OneShotInstrumentAdapter(checked_base_instrument, admission=gate)
epoch = adapter.start()
rows_receipt = adapter.instrument('account-snapshot', expected_epoch=epoch)
# A freshly observed selected node supplies the path and witness for later calls.
adapter.stop()
```

Opening admission creates no device connection. Closing admission closes only
the Python operation gate; its receipt makes no native release or persistent
connection claim. The current helper invokes Android `Instrumentation.finish`.
Android 16 framework source disconnects a non-destroyed UiAutomation object
before finishing instrumentation. This is the framework contract behind a
successfully completed checked transaction, not a separately measured connection
release or a guarantee about a timed-out transaction:

https://android.googlesource.com/platform/frameworks/base/+/android16-qpr2-release/core/java/android/app/Instrumentation.java

Each call requires the explicit admission epoch. Its reservation is recorded
under a lock before the bound driver executes. A concurrent call, stale epoch,
closed gate or unsupported request does not reach the driver. `stop` and `start`
refuse while a call is in flight rather than waiting and silently changing its
lifecycle underneath it. Requests are limited to the four account operations
supported by the published one-shot Java helper; explicit persistent-driver
pointer or scoped-card operations are deliberately unsupported.

Any driver exception, interruption or malformed/failing completion permanently
latches the owner gate as `uncertain`. Further calls, `start` and `stop` refuse.
There is no reset or replay API and no saved operation to replay. The owner must
not replace the gate to evade uncertainty. It must stop the known helper/app or
dispose of its owned VM through its separate cleanup path, retaining an honest
unproven-cleanup result when termination cannot be verified.

The gate retains flags and counts only. It never retains operation arguments,
tree payloads, witnesses, private input, exception objects or exception text in
metrics. An ordinary checked return is handed back to the authorized caller;
the caller still owns its existing node, authentication, privacy and capture
checks. Ordinary Python exception tracebacks can retain call-local arguments until
the caller releases them; the outer owner must not export raw tracebacks. The
retention claim here is limited to the gate instance and metrics.
This foundation does not replace those checks or the signed Root-review
protocol, and it does not prove any UI action or Phase1 acceptance.

Run the offline boundary suite from this directory:

```sh
python3 -B -m unittest -v test_oneshot_adapter.py
```

Tests use synthetic receipts and a real thread barrier to check reservation,
concurrent refusal, unknown-completion latching, stale epochs and safe metrics.
No test contacts a device or service or loads task-private credentials.
