package com.example.real_estate_mobile;

import org.junit.Test;
import java.util.ArrayList;
import java.util.List;
import static org.junit.Assert.*;

/** Pure state tests: executable on the JVM without Android, adb or network rules. */
public class Phase1FirstRunReadinessTest {
    private static final class Node implements Phase1UiStartupTest.IntroductionNode {
        String owner = "com.aqer.yemen.uat", text, description;
        boolean visible = true, enabled = true, clickable, clickResult = true;
        int clicks, childReads;
        Node parent;
        List<Node> children = new ArrayList<>();
        Node add(Node child) { children.add(child); if (child != null) child.parent = this; return this; }
        public String owner() { return owner; }
        public CharSequence text() { return text; }
        public CharSequence description() { return description; }
        public boolean visible() { return visible; }
        public boolean enabled() { return enabled; }
        public boolean clickable() { return clickable; }
        public boolean click() { clicks++; return clickResult; }
        public int childCount() { return children.size(); }
        public Node child(int index) { childReads++; return children.get(index); }
        public Node parent() { return parent; }
        public void recycle() { }
    }

    @Test public void childWalkFindsFlutterDescriptionAndClicksTheNearestButton() {
        Node root = new Node(), branch = new Node(), button = new Node();
        root.clickable = true; button.clickable = true;
        button.description = "المتابعة الآن";
        root.add(null).add(branch); branch.add(button);
        assertTrue(Phase1UiStartupTest.visitIntroduction(root, false));
        assertEquals(0, button.clicks);
        assertTrue(Phase1UiStartupTest.visitIntroduction(root, true));
        assertTrue(root.childReads > 0 && branch.childReads > 0);
        assertEquals(1, button.clicks); assertEquals(0, root.clicks);
    }

    @Test public void textChildClicksItsParentAndDoesNotMaskAnActionFailure() {
        Node root = new Node(), button = new Node(), label = new Node();
        root.clickable = true; button.clickable = true;
        label.text = "المتابعة الآن";
        root.add(button); button.add(label);
        assertTrue(Phase1UiStartupTest.visitIntroduction(root, true));
        assertEquals(1, button.clicks); assertEquals(0, label.clicks);
        button.clickResult = false;
        assertFalse(Phase1UiStartupTest.visitIntroduction(root, true));
        assertEquals(2, button.clicks); assertEquals(0, root.clicks);
    }

    @Test public void hiddenDisabledForeignAndMissingLabelsCannotBeClicked() {
        for (String kind : new String[] {"hidden", "disabled", "foreign", "missing"}) {
            Node root = new Node(), label = new Node();
            root.clickable = true; label.clickable = true; label.text = "المتابعة الآن";
            if (kind.equals("hidden")) label.visible = false;
            if (kind.equals("disabled")) label.enabled = false;
            if (kind.equals("foreign")) label.owner = "another.app";
            if (kind.equals("missing")) label.text = "اختيار المحافظة يدويًا";
            root.add(label);
            assertFalse(kind, Phase1UiStartupTest.visitIntroduction(root, true));
            assertEquals(0, label.clicks); assertEquals(0, root.clicks);
        }
    }

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
