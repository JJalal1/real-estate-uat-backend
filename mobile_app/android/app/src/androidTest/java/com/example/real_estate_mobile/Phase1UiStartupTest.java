package com.example.real_estate_mobile;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;

/** No accounts, fixtures, app hooks or API writes. The host blocks all IP egress. */
@SuppressWarnings("deprecation")
public class Phase1UiStartupTest {
    private static final String PACKAGE = "com.aqer.yemen.uat";
    private static final String CONTINUE_LABEL = "المتابعة الآن";

    static final class FirstRunReadiness {
        boolean continued, ready;
        long stableSince = -1;
        int samples;
        void onContinueClick() { continued = true; stableSince = -1; samples = 0; ready = false; }
        boolean observe(boolean introduction, boolean navigation, long now) {
            if (!continued || introduction || !navigation) {
                stableSince = -1; samples = 0; ready = false; return false;
            }
            if (stableSince < 0) stableSince = now;
            samples++;
            ready = samples >= 3 && now - stableSince >= 1000;
            return ready;
        }
        boolean canCapture(boolean introduction, boolean navigation) {
            return ready && !introduction && navigation;
        }
    }

    private boolean flutterVisible(View view) {
        if (view.getClass().getName().equals("io.flutter.embedding.android.FlutterView")
                && view.isShown() && view.getWidth() > 0 && view.getHeight() > 0) return true;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                if (flutterVisible(group.getChildAt(i))) return true;
            }
        }
        return false;
    }

    private Set<String> semanticKeys(AccessibilityNodeInfo root) {
        Set<String> found = new HashSet<>();
        ArrayDeque<AccessibilityNodeInfo> nodes = new ArrayDeque<>();
        nodes.add(AccessibilityNodeInfo.obtain(root));
        while (!nodes.isEmpty()) {
            AccessibilityNodeInfo node = nodes.removeFirst();
            String text = String.valueOf(node.getText()) + " " + String.valueOf(node.getContentDescription());
            if (node.isVisibleToUser() && text.contains("العقارات")) found.add("marketplace");
            if (node.isVisibleToUser() && text.contains("حسابي")) found.add("account");
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) nodes.add(child);
            }
            node.recycle();
        }
        return found;
    }

    private void denySystemPrompt(AccessibilityNodeInfo root) {
        String owner = String.valueOf(root.getPackageName());
        if (!owner.endsWith(".permissioncontroller")) return;
        for (String id : new String[] {"permission_deny_button", "permission_deny_and_dont_ask_again_button"}) {
            for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByViewId(owner + ":id/" + id)) {
                if (node.isClickable() && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return;
            }
        }
    }

    private boolean introductionVisible(AccessibilityNodeInfo root) {
        for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(CONTINUE_LABEL)) {
            if (node.isVisibleToUser()) return true;
        }
        return false;
    }

    private boolean continueIntroduction(AccessibilityNodeInfo root) {
        for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(CONTINUE_LABEL)) {
            while (node != null && PACKAGE.contentEquals(String.valueOf(node.getPackageName()))) {
                if (node.isVisibleToUser() && node.isEnabled() && node.isClickable()) {
                    return node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                }
                node = node.getParent();
            }
        }
        return false;
    }

    private boolean navigationVisible(Instrumentation instrumentation, Activity activity, AccessibilityNodeInfo root) {
        if (root == null || !PACKAGE.contentEquals(String.valueOf(root.getPackageName())) || introductionVisible(root)) return false;
        boolean[] flutter = {false};
        instrumentation.runOnMainSync(() -> flutter[0] = flutterVisible(activity.getWindow().getDecorView()));
        Set<String> keys = semanticKeys(root);
        return flutter[0] && keys.contains("marketplace") && keys.contains("account");
    }

    private boolean captureReady(Instrumentation instrumentation, Activity activity, UiAutomation automation, FirstRunReadiness readiness) {
        AccessibilityNodeInfo root = automation.getRootInActiveWindow();
        if (root == null) return false;
        try {
            return readiness.canCapture(introductionVisible(root), navigationVisible(instrumentation, activity, root));
        } finally { root.recycle(); }
    }

    @Test public void releaseShowsFlutterNavigationAndAnActualFrame() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        assertEquals(PACKAGE, instrumentation.getTargetContext().getPackageName());
        UiAutomation automation = instrumentation.getUiAutomation();
        Intent intent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                .setClassName(PACKAGE, "com.example.real_estate_mobile.MainActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Activity activity = instrumentation.startActivitySync(intent);
        long deadline = SystemClock.elapsedRealtime() + 45000;
        FirstRunReadiness readiness = new FirstRunReadiness();
        boolean observed = false;
        do {
            AccessibilityNodeInfo root = automation.getRootInActiveWindow();
            if (root != null) {
                try {
                    denySystemPrompt(root);
                    boolean introduction = introductionVisible(root);
                    if (!readiness.continued && introduction && continueIntroduction(root)) readiness.onContinueClick();
                    if (readiness.observe(introduction, navigationVisible(instrumentation, activity, root), SystemClock.elapsedRealtime())) {
                        observed = true; break;
                    }
                } finally { root.recycle(); }
            } else {
                readiness.observe(false, false, SystemClock.elapsedRealtime());
            }
            SystemClock.sleep(250);
        } while (SystemClock.elapsedRealtime() < deadline);
        assertTrue("First-run continuation and stable Flutter navigation were not observed", observed);
        assertTrue("Navigation changed before capture", captureReady(instrumentation, activity, automation, readiness));
        Bitmap frame = automation.takeScreenshot();
        assertNotNull("Android did not capture a frame", frame);
        assertTrue("Navigation changed during capture", captureReady(instrumentation, activity, automation, readiness));
        assertTrue(frame.getWidth() > 20 && frame.getHeight() > 20);
        // Ignore the OS bars: a clock on an otherwise black screen is insufficient.
        int marginX = frame.getWidth() / 20, marginY = frame.getHeight() / 20;
        int first = frame.getPixel(marginX, marginY);
        boolean varied = false;
        for (int y = marginY; y < frame.getHeight() - marginY && !varied; y += Math.max(1, frame.getHeight() / 100)) {
            for (int x = marginX; x < frame.getWidth() - marginX; x += Math.max(1, frame.getWidth() / 100)) {
                if (frame.getPixel(x, y) != first) { varied = true; break; }
            }
        }
        assertTrue("Only a uniform/black frame was captured", varied);
        File target = new File(instrumentation.getTargetContext().getCacheDir(), "phase1-ui-startup.png");
        try (FileOutputStream stream = new FileOutputStream(target)) {
            assertTrue(frame.compress(Bitmap.CompressFormat.PNG, 100, stream));
        }
        JSONObject proof = new JSONObject().put("package", PACKAGE)
                .put("version_code", instrumentation.getTargetContext().getPackageManager()
                        .getPackageInfo(PACKAGE, 0).getLongVersionCode())
                .put("flutter_view", true).put("nonuniform_frame", true)
                .put("first_run_continued", readiness.continued).put("navigation_stable", true).put("capture_rechecked", true)
                .put("semantic_keys", new JSONArray().put("marketplace").put("account"))
                .put("width", frame.getWidth()).put("height", frame.getHeight());
        frame.recycle();
        Bundle result = new Bundle();
        // Only allowlisted labels are reported, never the full accessibility tree.
        result.putString("aqer_ui_smoke", proof.toString());
        instrumentation.sendStatus(0, result);
    }
}
