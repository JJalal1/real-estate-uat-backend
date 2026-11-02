package com.example.real_estate_mobile;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONObject;
import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;
import org.junit.runner.notification.RunListener;

/** CI-only platform bootstrap. No shared AndroidX runner/lifecycle dependencies. */
public final class Phase1UiInstrumentation extends Instrumentation {
    private static volatile Instrumentation current;

    static Instrumentation instrumentation() {
        if (current == null) throw new IllegalStateException("Phase1 platform runner is required");
        return current;
    }

    private static String diagnosticType(Throwable failure) {
        if (failure instanceof NoSuchMethodError) return "NoSuchMethodError";
        if (failure instanceof NoClassDefFoundError) return "NoClassDefFoundError";
        if (failure instanceof AssertionError) return "AssertionError";
        if (failure instanceof SecurityException) return "SecurityException";
        if (failure instanceof IllegalStateException) return "IllegalStateException";
        return "RuntimeException";
    }

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        current = this;
        start();
    }

    @Override public void onStart() {
        Bundle output = new Bundle();
        int exit = Activity.RESULT_CANCELED;
        try {
            super.onStart();
            Bundle stage = new Bundle();
            stage.putString("aqer_ui_stage", "runner_bootstrap");
            sendStatus(1, stage);
            // Application.onCreate must complete before the UI suite starts.
            waitForIdleSync();
            stage.putString("aqer_ui_stage", "runner_junit_start");
            sendStatus(1, stage);
            AtomicInteger assumptions = new AtomicInteger();
            JUnitCore junit = new JUnitCore();
            junit.addListener(new RunListener() {
                @Override public void testAssumptionFailure(Failure failure) { assumptions.incrementAndGet(); }
            });
            // Exactly the original six readiness tests and one real UI test.
            Result result = junit.run(Phase1FirstRunReadinessTest.class, Phase1UiStartupTest.class);
            JSONObject counts = new JSONObject().put("run", result.getRunCount())
                    .put("failures", result.getFailureCount()).put("ignored", result.getIgnoreCount())
                    .put("assumptions", assumptions.get());
            Bundle status = new Bundle();
            status.putString("aqer_junit", counts.toString());
            sendStatus(0, status);
            boolean passed = result.wasSuccessful() && result.getRunCount() == 7
                    && result.getIgnoreCount() == 0 && assumptions.get() == 0;
            String summary = passed ? "\nOK (7 tests)\n" : "\nFAILURES!!!\n";
            if (!passed) {
                for (Failure failure : result.getFailures()) summary += diagnosticType(failure.getException()) + "\n";
            }
            output.putString(REPORT_KEY_STREAMRESULT, summary);
            if (passed) exit = Activity.RESULT_OK;
        } catch (Throwable failure) {
            // Fixed exception categories only; never messages, stack traces or UI text.
            output.putString(REPORT_KEY_STREAMRESULT, "\nFAILURES!!!\n" + diagnosticType(failure) + "\n");
        } finally {
            current = null;
            finish(exit, output);
        }
    }
}
