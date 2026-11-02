package com.example.real_estate_mobile;

import org.junit.Test;
import static org.junit.Assert.*;

/** Pure state tests: executable on the JVM without Android, adb or network rules. */
public class Phase1FirstRunReadinessTest {
    @Test public void freshInstallCannotPassBeforeTheDelayedIntroduction() {
        Phase1UiStartupTest.FirstRunReadiness state = new Phase1UiStartupTest.FirstRunReadiness();
        assertFalse(state.observe(false, true, 0));
        assertFalse(state.observe(false, true, 500));
        assertFalse(state.observe(false, true, 1000));
        assertFalse(state.observe(false, true, 5000));
        assertFalse(state.canCapture(false, true));
        assertFalse(state.observe(true, true, 6000));
        state.onContinueClick();
        assertFalse(state.observe(true, true, 6100));
        assertFalse(state.canCapture(true, true));
    }

    @Test public void continuationRequiresMultipleStableNavigationSamples() {
        Phase1UiStartupTest.FirstRunReadiness state = new Phase1UiStartupTest.FirstRunReadiness();
        state.onContinueClick();
        assertFalse(state.observe(false, true, 0));
        assertFalse(state.observe(false, true, 250));
        assertFalse(state.observe(false, true, 500));
        assertTrue(state.observe(false, true, 1000));
        assertTrue(state.canCapture(false, true));
        state.onContinueClick();
        assertFalse(state.observe(false, true, 2000));
        assertFalse(state.observe(false, true, 4000));
        assertTrue(state.observe(false, true, 4250));
    }

    @Test public void aModalOrLostNavigationAtCaptureCannotReuseEarlierReadiness() {
        Phase1UiStartupTest.FirstRunReadiness state = new Phase1UiStartupTest.FirstRunReadiness();
        state.onContinueClick();
        state.observe(false, true, 0); state.observe(false, true, 500);
        assertTrue(state.observe(false, true, 1000));
        assertFalse(state.canCapture(true, true));
        assertFalse(state.canCapture(false, false));
        assertFalse(state.observe(true, true, 1001));
        assertFalse(state.observe(false, true, 1500));
        assertFalse(state.observe(false, true, 2000));
        assertTrue(state.observe(false, true, 2500));
        assertFalse(state.observe(false, false, 2600));
        assertFalse(state.canCapture(false, true));
    }
}
