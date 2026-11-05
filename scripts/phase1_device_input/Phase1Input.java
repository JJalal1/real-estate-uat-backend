package com.aqer.phase1.input;

import android.app.Instrumentation;
import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.KeyEvent;
import android.view.KeyCharacterMap;
import android.view.accessibility.AccessibilityWindowInfo;
import android.view.accessibility.AccessibilityNodeInfo;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;

/** Disposable test-only input. No Activity, network, credential storage or shell identity. */
public final class Phase1Input extends Instrumentation {
    private static final String APP = "com.aqer.yemen.uat";
    private static final String QUERY = "شقة للإيجار";
    private Bundle args;
    private UiAutomation automation;
    private int events;
    private long firstUp, secondDown;
    private long firstUpReturn, secondDownReturn, origin, lastDown;
    private final List<Long> eventTimes = new ArrayList<>(), returnTimes = new ArrayList<>();
    private float[] lastX, lastY;
    private boolean pointerActive;
    private String stage="guard";
    private String foreground="UNOBSERVED";
    private int selectionContext; // 0=ordinary field observation, 1=initial, 2=pointer recheck
    private final DeadlineLease deadline=new DeadlineLease();
    private boolean imeKeyActive;
    private long imeKeyDownTime;
    private String imePhase="UNOBSERVED",imeSubstage="UNOBSERVED";
    private int imeObservations,imeWindowCount=-1,imeAppMatches=-1;


    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); args = arguments; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        String op = args == null ? "" : args.getString("op", "");
        try {
            require(Build.VERSION.SDK_INT == 36 && ("ranchu".equals(Build.HARDWARE) || "goldfish".equals(Build.HARDWARE)));
            stage="input_deadline_policy";
            long leaseElapsed=SystemClock.elapsedRealtime();
            deadline.configure(args.getString("deadline_utc_ms",null),System.currentTimeMillis(),leaseElapsed);
            stage="automation"; automation = getUiAutomation();
            origin = SystemClock.uptimeMillis();
            AccessibilityNodeInfo root = readyRoot(op); stage="root_ready";
            if (op.startsWith("account-")) {
                accountOperation(root, op, result);
            } else if ("empty-query".equals(op)) {
                require(!contains(root,"شروط البحث"));
                List<AccessibilityNodeInfo> fields=new ArrayList<>(); editable(root,fields);
                require(fields.size()==1 && !fields.get(0).isPassword());
                stage="query_verify";
                CharSequence text=fields.get(0).getText(), hint=fields.get(0).getHintText();
                require(text==null || text.length()==0 || (fields.get(0).isShowingHintText() &&
                    hint!=null && hint.toString().contentEquals(text)));
                result.putBoolean("empty_query_verified",true);
            } else if ("submit-query".equals(op)) {
                require(!contains(root,"شروط البحث"));
                List<AccessibilityNodeInfo> controls=new ArrayList<>();
                namedClickable(root,"تنفيذ",controls); require(controls.size()==1);
                stage="submit_action";
                require(checkedAction(controls.get(0),AccessibilityNodeInfo.ACTION_CLICK));
                SystemClock.sleep(500);
                result.putBoolean("semantic_click_delivered",true);
            } else if ("fixture-query".equals(op) || "negative-query".equals(op) || "clear-query".equals(op)) {
                require(contains(root, "البحث عن عقار") || contains(root, "البحث على الخريطة"));
                List<AccessibilityNodeInfo> fields = new ArrayList<>();
                editable(root, fields);
                require(fields.size() == 1);
                // Flutter3.27.3 exposes its Dart setText handler only while
                // focused. A bridge-side cached value is not a typed query.
                stage="query_focus";
                require(checkedAction(fields.get(0),AccessibilityNodeInfo.ACTION_CLICK));
                long focusDeadline=SystemClock.uptimeMillis()+5000;
                AccessibilityNodeInfo field=null;
                while(SystemClock.uptimeMillis()<focusDeadline) {
                    SystemClock.sleep(100);
                    List<AccessibilityNodeInfo> fresh=new ArrayList<>();
                    AccessibilityNodeInfo active=automation.getRootInActiveWindow();
                    if(active!=null) editable(active,fresh);
                    if(fresh.size()==1 && fresh.get(0).isFocused() &&
                       (fresh.get(0).getActions() & AccessibilityNodeInfo.ACTION_SET_TEXT)!=0) {
                        field=fresh.get(0); break;
                    }
                }
                require(field!=null);
                Bundle value = new Bundle();
                String query = "fixture-query".equals(op) ? QUERY : "clear-query".equals(op) ? "" : "phase1-ci-no-match";
                value.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, query);
                stage="query_action"; require(checkedAction(field,AccessibilityNodeInfo.ACTION_SET_TEXT,value));
                long deadline=SystemClock.uptimeMillis()+5000;
                boolean matched=false; stage="query_match";
                while(SystemClock.uptimeMillis()<deadline) {
                    SystemClock.sleep(100);
                    List<AccessibilityNodeInfo> fresh=new ArrayList<>();
                    AccessibilityNodeInfo active=automation.getRootInActiveWindow();
                    if(active!=null) editable(active,fresh);
                    if(fresh.size()==1 && fresh.get(0).isFocused()) {
                        CharSequence text=fresh.get(0).getText();
                        if(query.isEmpty() ? text==null||text.length()==0 : text!=null&&query.contentEquals(text)) { matched=true; break; }
                    }
                }
                require(matched);
                result.putBoolean("focused_set_text_handler", true);
                result.putBoolean("text_matched", true);
            } else {
                require("double-tap".equals(op) || "pinch-in".equals(op) || "pinch-out".equals(op));
                require(contains(root, "صورة العقار 1 من 1") && contains(root, "1/1"));
                int x = number("x", 300, 780), y = number("y", 400, 1520);
                if ("double-tap".equals(op)) {
                    stage="double_tap";
                    long down = SystemClock.uptimeMillis();
                    send(down, MotionEvent.ACTION_DOWN, new float[]{x}, new float[]{y});
                    SystemClock.sleep(35);
                    firstUp = send(down, MotionEvent.ACTION_UP, new float[]{x}, new float[]{y});
                    firstUpReturn = SystemClock.uptimeMillis();
                    SystemClock.sleep(80);
                    down = SystemClock.uptimeMillis();
                    secondDown = send(down, MotionEvent.ACTION_DOWN, new float[]{x}, new float[]{y});
                    secondDownReturn = SystemClock.uptimeMillis();
                    SystemClock.sleep(35);
                    send(down, MotionEvent.ACTION_UP, new float[]{x}, new float[]{y});
                    require(secondDown - firstUp >= 40 && secondDown - firstUp <= 300);
                    require(secondDown - firstUpReturn >= 40 && secondDownReturn - firstUp <= 300);
                    result.putLong("inter_tap_ms", secondDown - firstUp);
                    result.putLong("inter_tap_lower_ms", secondDown - firstUpReturn);
                    result.putLong("inter_tap_upper_ms", secondDownReturn - firstUp);
                } else {
                    stage="pinch";
                    boolean out = "pinch-out".equals(op);
                    float from = out ? 90 : 270, to = out ? 270 : 90;
                    long down = SystemClock.uptimeMillis();
                    send(down, MotionEvent.ACTION_DOWN, new float[]{x-from}, new float[]{y});
                    send(down, MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                        new float[]{x-from,x+from}, new float[]{y,y});
                    for (int i = 1; i <= 15; i++) {
                        SystemClock.sleep(20);
                        float span = from + (to-from)*i/15;
                        send(down, MotionEvent.ACTION_MOVE, new float[]{x-span,x+span}, new float[]{y,y});
                    }
                    send(down, MotionEvent.ACTION_POINTER_UP | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                        new float[]{x-to,x+to}, new float[]{y,y});
                    send(down, MotionEvent.ACTION_UP, new float[]{x-to}, new float[]{y});
                }
                SystemClock.sleep(600);
                result.putInt("events", events);
                result.putString("event_ms", numbers(eventTimes));
                result.putString("return_ms", numbers(returnTimes));
            }
            result.putBoolean("deadline_capable",true);
            result.putBoolean("deadline_enforced",deadline.enabled);
            stage="complete"; result.putString("op", op);
            result.putBoolean("passed", true);
            finish(-1, result);
        } catch (Throwable failure) {
            cancelPointer(); cancelImeKey();
            // Never return arbitrary exception text, accessibility content or stack traces.
            result.putString("op", safeOp(op));
            result.putBoolean("passed", false);
            result.putBoolean("deadline_capable",true);
            result.putBoolean("deadline_enforced",deadline.enabled);
            result.putInt("events", events);
            result.putString("stage", stage);
            result.putString("foreground_category", foreground);
            result.putString("event_ms", numbers(eventTimes));
            result.putString("return_ms", numbers(returnTimes));
            result.putString("reason", "input_precondition_or_delivery_failed");
            if("account-dismiss-ime".equals(op) && !"UNOBSERVED".equals(imePhase)) {
                result.putString("ime_observation_phase",imePhase);
                result.putString("ime_observation_substage",imeSubstage);
                result.putInt("ime_observation_count",imeObservations);
                if(imeWindowCount>=0) result.putInt("ime_window_count",imeWindowCount);
                if(imeAppMatches>=0) result.putInt("ime_focused_app_matches",imeAppMatches);
            }
            finish(0, result);
        }
    }
    private AccessibilityNodeInfo readyRoot(String op) {
        long deadline=SystemClock.uptimeMillis()+5000;
        while(SystemClock.uptimeMillis()<deadline) {
            if(op.startsWith("account-")) {
                stage="account_cache_clear";
                // A preceding OS uiautomator dump may still be releasing its
                // connection. Observe readiness before any account operation;
                // never read a stale cache or dispatch/replay input here.
                if(!automation.clearCache()) { SystemClock.sleep(100); continue; }
            }
            AccessibilityNodeInfo root=automation.getRootInActiveWindow();
            CharSequence rootPackage=root==null ? null : root.getPackageName();
            foreground=foregroundCategory(rootPackage);
            if(root!=null && rootPackage!=null && APP.contentEquals(rootPackage)) {
                boolean query="fixture-query".equals(op)||"negative-query".equals(op)||"clear-query".equals(op)||"submit-query".equals(op)||"empty-query".equals(op);
                if(op.startsWith("account-") || (query ? contains(root,"البحث عن عقار")||contains(root,"البحث على الخريطة")
                         : contains(root,"صورة العقار 1 من 1")&&contains(root,"1/1"))) return root;
            }
            SystemClock.sleep(100);
        }
        throw new IllegalStateException();
    }
    private static String foregroundCategory(CharSequence packageName) {
        if(packageName==null || packageName.length()==0) return "UNOBSERVED";
        if(APP.contentEquals(packageName)) return "APP";
        if("com.google.android.permissioncontroller".contentEquals(packageName) ||
           "com.android.permissioncontroller".contentEquals(packageName)) return "PERMISSION_CONTROLLER";
        if("com.google.android.documentsui".contentEquals(packageName) ||
           "com.android.documentsui".contentEquals(packageName) ||
           "com.google.android.providers.media.module".contentEquals(packageName) ||
           "com.android.providers.media.module".contentEquals(packageName)) return "DOCUMENT_PICKER";
        if("com.android.systemui".contentEquals(packageName)) return "SYSTEM_UI";
        return "OTHER";
    }
    private static String numbers(List<Long> values) {
        StringBuilder text=new StringBuilder();
        for(Long value:values) { if(text.length()>0) text.append(','); text.append(value); }
        return text.toString();
    }
    private void cancelPointer() {
        if(!pointerActive || automation==null || lastX==null) return;
        try { send(lastDown,MotionEvent.ACTION_CANCEL,lastX,lastY); } catch(Throwable ignored) { }
        pointerActive=false;
    }
    private static String safeOp(String op) {
        return "account-dismiss-ime".equals(op) || "account-snapshot".equals(op) || "account-click".equals(op) || "account-set".equals(op) || "account-scroll".equals(op) || "fixture-query".equals(op) || "negative-query".equals(op) || "clear-query".equals(op) || "submit-query".equals(op) || "empty-query".equals(op) || "double-tap".equals(op)
            || "pinch-in".equals(op) || "pinch-out".equals(op) ? op : "invalid";
    }
    private static String plain(CharSequence value) { return value==null ? "" : value.toString(); }
    private static String accessibleDescription(AccessibilityNodeInfo node) {
        String description=plain(node.getContentDescription()),tooltip=plain(node.getTooltipText());
        if(description.isEmpty()) return tooltip;
        if(tooltip.isEmpty() || description.equals(tooltip)) return description;
        return description+"\n"+tooltip;
    }
    private static String witness(AccessibilityNodeInfo node) throws Exception {
        Rect rect=new Rect(); node.getBoundsInScreen(rect);
        String raw=plain(node.getPackageName())+"|"+plain(node.getClassName())+"|"+safeLabel(node.getText(),node.isPassword())+"|"+safeLabel(accessibleDescription(node),node.isPassword())+"|"+rect.flattenToString();
        byte[] hash=MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex=new StringBuilder(); for(byte b:hash) hex.append(String.format("%02x",b&255)); return hex.toString();
    }
    private static String safeLabel(CharSequence value, boolean password) {
        String text=plain(value); return password ? "[redacted]" : text.replaceAll("(?<![0-9٠-٩۰-۹])[0-9٠-٩۰-۹]{6}(?![0-9٠-٩۰-۹])","[redacted]");
    }
    private static void snapshot(AccessibilityNodeInfo node,String path,JSONArray nodes,int depth) throws Exception {
        if(depth>40 || nodes.length()>=1200) return;
        Rect r=new Rect(); node.getBoundsInScreen(r);
        JSONObject row=new JSONObject(); row.put("path",path); row.put("class",plain(node.getClassName()));
        row.put("text",safeLabel(node.getText(),node.isPassword())); row.put("description",safeLabel(accessibleDescription(node),node.isPassword()));
        row.put("hint",safeLabel(node.getHintText(),node.isPassword())); row.put("package",plain(node.getPackageName()));
        row.put("bounds",new JSONArray(new int[]{r.left,r.top,r.right,r.bottom})); row.put("witness",witness(node));
        row.put("editable",node.isEditable()); row.put("clickable",node.isClickable()); row.put("scrollable",node.isScrollable());
        row.put("visible",node.isVisibleToUser()); row.put("enabled",node.isEnabled()); row.put("focused",node.isFocused()); row.put("password",node.isPassword()); row.put("actions",node.getActions());
        nodes.put(row);
        for(int i=0;i<node.getChildCount();i++) { AccessibilityNodeInfo child=node.getChild(i); if(child!=null) snapshot(child,path+"."+i,nodes,depth+1); }
    }
    private static final class Selection {
        final AccessibilityNodeInfo root,node;
        Selection(AccessibilityNodeInfo root,AccessibilityNodeInfo node) { this.root=root; this.node=node; }
    }
    private AccessibilityNodeInfo selected(AccessibilityNodeInfo root) throws Exception {
        return selectedExpected(false).node;
    }
    private Selection selectedExpected(boolean pointerRecheck) throws Exception {
        return selectedExpected(pointerRecheck,SystemClock.uptimeMillis()+1000L);
    }
    private Selection selectedExpected(boolean pointerRecheck,long end) throws Exception {
        if(pointerRecheck) stage="pointer_input_guard"; else stage="initial_input_guard";
        require(events==0 && !pointerActive);
        selectionContext=pointerRecheck ? 2 : 1;
        try {
            if(pointerRecheck) stage="pointer_path_format"; else stage="initial_path_format";
            String path=args.getString("node_path",""); require(path.matches("0(?:\\.[0-9]{1,4}){0,40}"));
            if(pointerRecheck) stage="pointer_witness_format"; else stage="initial_witness_format";
            final String expected=args.getString("node_witness",""); require(expected.matches("[a-f0-9]{64}"));
            int reads=0;
            while(true) {
                if(SystemClock.uptimeMillis()>=end) throw new IllegalStateException();
                if(pointerRecheck) stage="pointer_cache_clear"; else stage="initial_cache_clear";
                require(automation.clearCache());
                AccessibilityNodeInfo fresh=automation.getRootInActiveWindow();
                CharSequence pkg=fresh==null ? null : fresh.getPackageName(); foreground=foregroundCategory(pkg);
                if(pointerRecheck) stage="pointer_root_guard"; else stage="initial_root_guard";
                require(fresh!=null && pkg!=null && APP.contentEquals(pkg));
                reads++;
                AccessibilityNodeInfo node=null;
                try { node=atPath(fresh,path); }
                catch(IllegalStateException unavailable) {
                    if(reads>=10 || SystemClock.uptimeMillis()>=end) throw unavailable;
                }
                if(node!=null) {
                    if(pointerRecheck) stage="pointer_witness_match"; else stage="initial_witness_match";
                    if(expected.equals(witness(node))) return new Selection(fresh,node);
                }
                if(reads>=10 || SystemClock.uptimeMillis()>=end) throw new IllegalStateException();
                // Only another observation of the SAME path and expected witness.
                // No input, new witness adoption, target search or retry occurs here.
                SystemClock.sleep(100);
            }
        } finally { selectionContext=0; }
    }
    private AccessibilityNodeInfo atPath(AccessibilityNodeInfo root,String path) throws Exception {
        stage="selected_path_resolve";
        if(selectionContext==1) stage="initial_path_resolve";
        else if(selectionContext==2) stage="pointer_path_resolve";
        AccessibilityNodeInfo node=root;
        String[] parts=path.split("\\.");
        for(int i=1;i<parts.length;i++) { int n=Integer.parseInt(parts[i]); require(n<node.getChildCount()); node=node.getChild(n); require(node!=null); }
        stage="selected_node_guard";
        if(selectionContext==1) stage="initial_node_guard";
        else if(selectionContext==2) stage="pointer_node_guard";
        require(node.getPackageName()!=null && APP.contentEquals(node.getPackageName()) && node.isVisibleToUser() && node.isEnabled());
        return node;
    }
    private void accountOperation(AccessibilityNodeInfo root,String op,Bundle result) throws Exception {
        stage="account_input_policy";
        String inputMode=args.getString("input_mode","semantic");
        require("semantic".equals(inputMode) || "physical_click_focus".equals(inputMode) || "physical_scroll".equals(inputMode));
        boolean physicalClickFocus="physical_click_focus".equals(inputMode);
        boolean physicalScroll="physical_scroll".equals(inputMode);
        require(!physicalClickFocus || "account-click".equals(op) || "account-set".equals(op));
        require(!physicalScroll || "account-scroll".equals(op));
        String scrollStep=args.getString("scroll_step","normal");
        require("normal".equals(scrollStep) || "short".equals(scrollStep));
        require(!args.containsKey("scroll_step") || ("account-scroll".equals(op) && physicalScroll));
        if("account-dismiss-ime".equals(op)) { dismissIme(result); return; }
        if("account-snapshot".equals(op)) {
            // Attaching a fresh UiAutomation can trigger Flutter semantics
            // updates after the APP root itself is already available. Wait
            // read-only for that event burst, then reacquire the actual root.
            // A busy UI may time out; that is not a successful idle claim.
            stage="account_snapshot_settle";
            try { automation.waitForIdle(250,1500); }
            catch(java.util.concurrent.TimeoutException busy) { }
            AccessibilityNodeInfo observed=readyRoot(op);
            JSONArray nodes=new JSONArray(); snapshot(observed,"0",nodes,0);
            String encoded=Base64.encodeToString(nodes.toString().getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP);
            result.putString("tree_b64",encoded); return;
        }
        if("account-set".equals(op)) {
            // Observe prior IME/layout event settling before binding a source
            // node. A timeout is not an idle-success claim or permission to
            // replace the caller's exact path/witness.
            stage="account_set_settle";
            try { automation.waitForIdle(250,1500); }
            catch(java.util.concurrent.TimeoutException busy) { }
            root=readyRoot(op);
        }
        AccessibilityNodeInfo node=selected(root);
        if("account-click".equals(op)) {
            stage="account_click";
            if(!physicalClickFocus && (node.getActions()&AccessibilityNodeInfo.ACTION_CLICK)!=0) {
                require(checkedAction(node,AccessibilityNodeInfo.ACTION_CLICK)); result.putBoolean("semantic_action_used",true);
            } else {
                require(node.isClickable() || node.isEditable() || "android.widget.Button".contentEquals(node.getClassName()));
                stage="account_pointer_tap"; pointerTap(node); result.putBoolean("native_pointer_used",true); result.putInt("native_pointer_events",events);
            }
        } else if("account-scroll".equals(op)) {
            stage="account_scroll"; int action="backward".equals(args.getString("direction","forward")) ? AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD : AccessibilityNodeInfo.ACTION_SCROLL_FORWARD;
            require(node.isScrollable());
            if(!physicalScroll && (node.getActions()&action)!=0) { require(checkedAction(node,action)); result.putBoolean("semantic_action_used",true); }
            else { stage="account_pointer_swipe"; pointerSwipe(node,"backward".equals(args.getString("direction","forward")),"short".equals(scrollStep)); result.putBoolean("native_pointer_used",true); result.putInt("native_pointer_events",events); }
        } else {
            require("account-set".equals(op) && node.isEditable()); stage="account_focus";
            String encoded=args.getString("value_b64",""); require(encoded.length()<=12000 && encoded.matches("[A-Za-z0-9+/=]*"));
            String value=new String(Base64.decode(encoded,Base64.NO_WRAP),StandardCharsets.UTF_8); require(value.length()<=5000);
            if(!node.isFocused()) {
                stage="account_focus_request";
                if(physicalClickFocus) require(node.isClickable() || node.isEditable() || "android.widget.Button".contentEquals(node.getClassName()));
                if(!physicalClickFocus && (node.getActions()&AccessibilityNodeInfo.ACTION_CLICK)!=0) require(checkedAction(node,AccessibilityNodeInfo.ACTION_CLICK));
                else { stage="account_focus_pointer"; pointerTap(node); result.putBoolean("native_pointer_used",true); result.putInt("native_pointer_events",events); }
            }
            stage="account_focus_observe";
            AccessibilityNodeInfo field=null; long end=SystemClock.uptimeMillis()+15000;
            int focusObservations=0;
            while(SystemClock.uptimeMillis()<end) {
                SystemClock.sleep(100); stage="account_focus_cache_clear"; require(automation.clearCache());
                AccessibilityNodeInfo fresh=automation.getRootInActiveWindow();
                CharSequence rootPackage=fresh==null ? null : fresh.getPackageName();
                foreground=foregroundCategory(rootPackage);
                if(fresh==null || !APP.contentEquals(rootPackage)) continue;
                // The pointer target was bound twice by exact path/witness.
                // Keyboard/layout reflow may move that node's tree index.
                // Follow only the currently focused original Android node;
                // never choose another field by its label or repeat focus.
                AccessibilityNodeInfo candidate=fresh.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
                stage="account_focus_pending";
                if(candidate==null) continue;
                boolean sameNode=node.equals(candidate);
                String originalHint=plain(node.getHintText()),currentHint=plain(candidate.getHintText());
                result.putString("focus_hint_transition",originalHint.equals(currentHint) ? "SAME" :
                    currentHint.isEmpty() ? "NONEMPTY_TO_EMPTY" : originalHint.isEmpty() ? "EMPTY_TO_NONEMPTY" : "NONEMPTY_CHANGED");
                result.putString("focus_hint_original_shape",focusHintShape(originalHint));
                result.putString("focus_hint_current_shape",focusHintShape(currentHint));
                result.putBoolean("focus_source_node_same",sameNode);
                result.putBoolean("focus_observed_focused",candidate.isFocused());
                result.putInt("focus_observation_count",++focusObservations);
                if(!sameNode) continue;
                require(APP.contentEquals(candidate.getPackageName()) && candidate.isVisibleToUser() && candidate.isEnabled());
                stage="account_focus_editable_match"; require(candidate.isEditable());
                stage="account_focus_class_match"; require(plain(node.getClassName()).equals(plain(candidate.getClassName())));
                stage="account_focus_description_match"; require(accessibleDescription(node).equals(accessibleDescription(candidate)));
                stage="account_focus_hint_match";
                if(!focusHintMatches(originalHint,currentHint,candidate.isFocused(),sameNode)) continue;
                stage="account_focus_pending";
                if(candidate.isFocused()) {
                    stage="account_focus_text_action_pending";
                    if((candidate.getActions()&AccessibilityNodeInfo.ACTION_SET_TEXT)!=0) field=candidate;
                }
                if(field!=null) break;
            }
            require(field!=null); stage="account_set_request";
            Bundle text=new Bundle(); text.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,value);
            require(checkedAction(field,AccessibilityNodeInfo.ACTION_SET_TEXT,text));
            result.putBoolean("set_text_delivered",true);
            // Never echo input contents, lengths, arbitrary exceptions or stack traces.
        }
        SystemClock.sleep(300); result.putBoolean("account_action_delivered",true);
    }
    private static boolean focusHintMatches(String original,String current,boolean focused,boolean sameNode) {
        // Pinned Flutter3.27.3 retains the InputDecorator label and includes
        // its focused hint in the merged label with an exact newline join.
        // The AI brief uses floatingLabelBehavior.never: after its label fades,
        // only the fixed hint remains. Each transition belongs to the SAME
        // focused Android source/window node; no substring rule.
        return original.equals(current) ||
            (sameNode && focused && ((!original.isEmpty() && current.isEmpty()) ||
                ("غرف النوم *".equals(original) && "غرف النوم *\nمثال: 3".equals(current)) ||
                ("الحمامات *".equals(original) && "الحمامات *\nمثال: 2".equals(current)) ||
                ("الإيجار الشهري بالريال اليمني *".equals(original) && "الإيجار الشهري بالريال اليمني *\n0".equals(current)) ||
                ("نسبة السعي %".equals(original) && "نسبة السعي %\n0".equals(current)) ||
                ("صف العقار".equals(original) && "النوع، الموقع، الغرف، الدور، الإيجار أو السعر…".equals(current))));
    }
    private static String focusHintShape(String value) {
        // Diagnostic categories only: no hint contents are returned, and this
        // classification never decides whether a focus transition is allowed.
        if(value.isEmpty()) return "EMPTY";
        if("غرف النوم *".equals(value)) return "BEDROOMS_LABEL";
        if("مثال: 3".equals(value)) return "BEDROOMS_EXAMPLE";
        if("الحمامات *".equals(value)) return "BATHROOMS_LABEL";
        if("مثال: 2".equals(value)) return "BATHROOMS_EXAMPLE";
        if("صف العقار".equals(value)) return "AI_BRIEF_LABEL";
        if("النوع، الموقع، الغرف، الدور، الإيجار أو السعر…".equals(value)) return "AI_BRIEF_HINT";
        if("صف العقار\nالنوع، الموقع، الغرف، الدور، الإيجار أو السعر…".equals(value)) return "AI_BRIEF_LABEL_AND_HINT";
        if("الإيجار الشهري بالريال اليمني *".equals(value)) return "MONTHLY_RENT_LABEL";
        if("الإيجار الشهري بالريال اليمني *\n0".equals(value)) return "MONTHLY_RENT_LABEL_AND_ZERO";
        if("نسبة السعي %".equals(value)) return "SAI_RATE_LABEL";
        if("نسبة السعي %\n0".equals(value)) return "SAI_RATE_LABEL_AND_ZERO";
        if("0".equals(value)) return "ZERO_HINT";
        if(value.contains("غرف النوم *") && value.contains("مثال: 3")) return "BEDROOMS_LABEL_AND_EXAMPLE";
        if(value.contains("الحمامات *") && value.contains("مثال: 2")) return "BATHROOMS_LABEL_AND_EXAMPLE";
        return "OTHER";
    }
    private Rect pointerBounds(AccessibilityNodeInfo node) throws Exception {
        final long end=SystemClock.uptimeMillis()+1000L;
        Selection selection=selectedExpected(true,end);
        AccessibilityNodeInfo active=selection.root,fresh=selection.node;
        stage="pointer_target_guard";
        String op=args.getString("op","");
        if("account-scroll".equals(op)) require(fresh.isScrollable());
        else if("account-set".equals(op)) require(fresh.isEditable());
        else { require("account-click".equals(op)); require(fresh.isClickable() || fresh.isEditable() || "android.widget.Button".contentEquals(fresh.getClassName())); }
        Rect screen=new Rect(), bounds=new Rect(); active.getBoundsInScreen(screen); fresh.getBoundsInScreen(bounds);
        stage="pointer_bounds_width"; require(bounds.width()>8);
        stage="pointer_bounds_height"; require(bounds.height()>8);
        stage="pointer_bounds_containment"; require(screen.contains(bounds));
        if("account-set".equals(op)) {
            // Both observations remain inside the ONE pointer-selection
            // deadline. Never adopt a replacement source, target or witness.
            stage="pointer_focus_source_match"; require(node.equals(fresh));
            stage="pointer_focus_stable_wait"; SystemClock.sleep(100);
            stage="pointer_focus_stable_deadline"; require(SystemClock.uptimeMillis()<end);
            stage="pointer_focus_stable_cache_clear"; require(automation.clearCache());
            AccessibilityNodeInfo stableRoot=automation.getRootInActiveWindow();
            CharSequence pkg=stableRoot==null ? null : stableRoot.getPackageName();
            foreground=foregroundCategory(pkg);
            stage="pointer_focus_stable_root_guard";
            require(stableRoot!=null && pkg!=null && APP.contentEquals(pkg));
            AccessibilityNodeInfo stable=atPath(stableRoot,args.getString("node_path",""));
            stage="pointer_focus_stable_source_match";
            require(node.equals(stable) && stable.isEditable());
            stage="pointer_focus_stable_witness_match";
            require(args.getString("node_witness","").equals(witness(stable)));
            Rect stableScreen=new Rect(),stableBounds=new Rect();
            stableRoot.getBoundsInScreen(stableScreen); stable.getBoundsInScreen(stableBounds);
            stage="pointer_focus_stable_bounds_match";
            require(screen.equals(stableScreen) && bounds.equals(stableBounds));
            stage="pointer_focus_stable_deadline"; require(SystemClock.uptimeMillis()<end);
        }
        return bounds;
    }
    private void pointerTap(AccessibilityNodeInfo node) throws Exception {
        String dispatchStage=stage;
        Rect b=pointerBounds(node); stage=dispatchStage;
        float x=b.exactCenterX(),y=b.exactCenterY(); long down=SystemClock.uptimeMillis();
        send(down,MotionEvent.ACTION_DOWN,new float[]{x},new float[]{y}); SystemClock.sleep(60);
        send(down,MotionEvent.ACTION_UP,new float[]{x},new float[]{y});
    }
    private void pointerSwipe(AccessibilityNodeInfo node,boolean backward,boolean shortStep) throws Exception {
        String dispatchStage=stage;
        Rect b=pointerBounds(node); stage=dispatchStage;
        stage="pointer_swipe_height"; require(b.height()>80); stage=dispatchStage;
        float[] span=scrollVerticalSpan(b.top,b.bottom,backward,shortStep);
        float x=b.exactCenterX(),from=span[0],to=span[1];
        long down=SystemClock.uptimeMillis();send(down,MotionEvent.ACTION_DOWN,new float[]{x},new float[]{from});
        for(int i=1;i<=12;i++){SystemClock.sleep(25);send(down,MotionEvent.ACTION_MOVE,new float[]{x},new float[]{from+(to-from)*i/12f});}
        send(down,MotionEvent.ACTION_UP,new float[]{x},new float[]{to});
    }
    private static float[] scrollVerticalSpan(int top,int bottom,boolean backward,boolean shortStep) {
        require(bottom-top>80);
        float margin=Math.min(60,(bottom-top)/4f);
        if(shortStep) {
            float center=top+(bottom-top)/2f,half=(bottom-top-2*margin)/6f;
            return backward?new float[]{center-half,center+half}:new float[]{center+half,center-half};
        }
        return backward?new float[]{top+margin,bottom-margin}:new float[]{bottom-margin,top+margin};
    }
    private int number(String key, int min, int max) {
        int value = Integer.parseInt(args.getString(key, "-1")); require(value >= min && value <= max); return value;
    }
    private static void require(boolean value) { if (!value) throw new IllegalStateException(); }
    private static boolean contains(AccessibilityNodeInfo node, String expected) {
        for (CharSequence value : new CharSequence[]{node.getText(), node.getContentDescription()}) {
            if (value != null) for (String line : value.toString().split("\n")) if (expected.equals(line.trim())) return true;
        }
        for (int i=0; i<node.getChildCount(); i++) { AccessibilityNodeInfo child=node.getChild(i); if(child!=null && contains(child,expected)) return true; }
        return false;
    }
    private static void editable(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> fields) {
        if (node.getPackageName()!=null && APP.contentEquals(node.getPackageName()) && node.isVisibleToUser() && node.isEnabled() && node.isEditable()) fields.add(node);
        for (int i=0; i<node.getChildCount(); i++) { AccessibilityNodeInfo child=node.getChild(i); if(child!=null) editable(child,fields); }
    }
    private static void namedClickable(AccessibilityNodeInfo node,String text,List<AccessibilityNodeInfo> result) {
        boolean match=false;
        for(CharSequence value:new CharSequence[]{node.getText(),node.getContentDescription()})
            if(value!=null) for(String line:value.toString().split("\n")) if(text.equals(line.trim())) match=true;
        if(match && node.getPackageName()!=null && APP.contentEquals(node.getPackageName()) &&
           node.isVisibleToUser() && node.isEnabled() && node.isClickable() &&
           (node.getActions() & AccessibilityNodeInfo.ACTION_CLICK)!=0) result.add(node);
        for(int i=0;i<node.getChildCount();i++) { AccessibilityNodeInfo child=node.getChild(i); if(child!=null) namedClickable(child,text,result); }
    }
    private long send(long down, int action, float[] xs, float[] ys) {
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[xs.length];
        MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[xs.length];
        for (int i=0; i<xs.length; i++) {
            properties[i]=new MotionEvent.PointerProperties(); properties[i].id=i; properties[i].toolType=MotionEvent.TOOL_TYPE_FINGER;
            coords[i]=new MotionEvent.PointerCoords(); coords[i].x=xs[i]; coords[i].y=ys[i]; coords[i].size=1;
            coords[i].pressure=(action & MotionEvent.ACTION_MASK)==MotionEvent.ACTION_UP || ((action & MotionEvent.ACTION_MASK)==MotionEvent.ACTION_POINTER_UP && i==1) ? 0 : 1;
        }
        long when=SystemClock.uptimeMillis();
        lastDown=down; lastX=xs; lastY=ys;
        boolean ending=(action & MotionEvent.ACTION_MASK)==MotionEvent.ACTION_UP || (action & MotionEvent.ACTION_MASK)==MotionEvent.ACTION_CANCEL;
        MotionEvent event=MotionEvent.obtain(down,when,action,xs.length,properties,coords,0,0,1,1,0,0,InputDevice.SOURCE_TOUCHSCREEN,0);
        try {
            if(!(ending && pointerActive)) requireLiveMutation();
            if(!ending) pointerActive=true;
            require(automation.injectInputEvent(event,true)); events++;
            if(ending) pointerActive=false;
            eventTimes.add(when-origin); returnTimes.add(SystemClock.uptimeMillis()-origin);
        } finally { event.recycle(); }
        return when;
    }
    // The absolute signed expiry is never renewed. This lease is initialized once
    // per checked one-shot transaction; the host retains the same grant deadline.
    private static final class DeadlineLease {
        private boolean initialized,enabled;
        private long utcExpiry,elapsedExpiry;
        void configure(String raw,long utcNow,long elapsedNow) {
            require(!initialized); initialized=true;
            if(raw==null) return;
            require(raw.matches("[1-9][0-9]{12}"));
            long expiry=Long.parseLong(raw);
            require(expiry>utcNow && expiry-utcNow<=120000L && elapsedNow>=0);
            require(elapsedNow<=Long.MAX_VALUE-(expiry-utcNow));
            utcExpiry=expiry; elapsedExpiry=elapsedNow+(expiry-utcNow); enabled=true;
        }
        boolean live(long utcNow,long elapsedNow) {
            return !enabled || (utcNow<utcExpiry && elapsedNow<elapsedExpiry);
        }
    }
    private void requireLiveMutation() {
        if(deadline.enabled && !deadline.live(System.currentTimeMillis(),SystemClock.elapsedRealtime())) {
            stage="input_deadline_expired"; throw new IllegalStateException();
        }
    }
    private boolean checkedAction(AccessibilityNodeInfo node,int action) {
        requireLiveMutation(); return node.performAction(action);
    }
    private boolean checkedAction(AccessibilityNodeInfo node,int action,Bundle value) {
        requireLiveMutation(); return node.performAction(action,value);
    }
    private static final class ImeObservation {
        final boolean visible; final int windowId; final AccessibilityNodeInfo focus;
        ImeObservation(boolean visible,int windowId,AccessibilityNodeInfo focus) {
            this.visible=visible; this.windowId=windowId; this.focus=focus;
        }
    }
    private ImeObservation inspectIme() {
        stage="ime_windows";
        imeObservations=Math.min(150,imeObservations+1); imeWindowCount=-1; imeAppMatches=-1;
        // Window and node observations must be fresh after IME/layout changes.
        // Retry observations only within the original bound; never repeat Back.
        imeSubstage="CACHE_CLEAR";
        require(automation.clearCache());
        imeSubstage="SERVICE_FLAGS";
        AccessibilityServiceInfo info=automation.getServiceInfo();
        require(info!=null && (info.flags & AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS)!=0);
        imeSubstage="WINDOW_LIST";
        List<AccessibilityWindowInfo> windows=automation.getWindows();
        if(windows!=null) imeWindowCount=Math.min(33,windows.size());
        require(windows!=null && !windows.isEmpty() && windows.size()<=32);
        AccessibilityNodeInfo appRoot=null; int appWindow=-1,appMatches=0; boolean ime=false;
        for(AccessibilityWindowInfo window:windows) {
            imeSubstage="WINDOW_ENTRY";
            require(window!=null);
            if(window.getType()==AccessibilityWindowInfo.TYPE_INPUT_METHOD) ime=true;
            if(window.getType()!=AccessibilityWindowInfo.TYPE_APPLICATION || !window.isFocused()) continue;
            AccessibilityNodeInfo candidate=window.getRoot();
            if(candidate!=null && candidate.getPackageName()!=null && APP.contentEquals(candidate.getPackageName())) {
                imeSubstage="APP_ROOT";
                require(candidate.isVisibleToUser() && candidate.isEnabled());
                appRoot=candidate; appWindow=window.getId(); appMatches++;
            }
        }
        imeAppMatches=Math.min(2,appMatches); imeSubstage="APP_WINDOW_UNIQUE";
        require(appMatches==1 && appRoot!=null); foreground="APP";
        AccessibilityNodeInfo focus=appRoot.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if(ime) {
            stage="ime_focus";
            imeSubstage="FOCUSED_EDITABLE";
            require(focus!=null && focus.getPackageName()!=null && APP.contentEquals(focus.getPackageName())
                && focus.isFocused() && focus.isEditable() && focus.isVisibleToUser() && focus.isEnabled());
        }
        imeSubstage="READY";
        return new ImeObservation(ime,appWindow,focus);
    }
    private ImeObservation observeImeUntil(long end) {
        while(SystemClock.elapsedRealtime()<end) {
            requireLiveMutation(); // Observe only under the ORIGINAL guest expiry.
            ImeObservation observed=null;
            try { observed=inspectIme(); }
            catch(IllegalStateException unavailable) { }
            requireLiveMutation(); // A blocking read cannot cross that expiry.
            if(SystemClock.elapsedRealtime()>=end) break;
            if(observed!=null) return observed;
            SystemClock.sleep(Math.max(0L,Math.min(100L,end-SystemClock.elapsedRealtime())));
        }
        throw new IllegalStateException();
    }
    private void sendImeKey(int action,boolean cancelled) {
        require(action==KeyEvent.ACTION_DOWN || action==KeyEvent.ACTION_UP);
        boolean releasing=action==KeyEvent.ACTION_UP && imeKeyActive;
        if(!releasing) requireLiveMutation();
        long now=SystemClock.uptimeMillis();
        if(action==KeyEvent.ACTION_DOWN) { require(!imeKeyActive); imeKeyDownTime=now; }
        KeyEvent event=new KeyEvent(imeKeyDownTime,now,action,KeyEvent.KEYCODE_BACK,0,0,
            KeyCharacterMap.VIRTUAL_KEYBOARD,0,cancelled ? KeyEvent.FLAG_CANCELED : 0,InputDevice.SOURCE_KEYBOARD);
        if(!releasing) requireLiveMutation();
        if(action==KeyEvent.ACTION_DOWN) imeKeyActive=true;
        require(automation.injectInputEvent(event,true));
        if(action==KeyEvent.ACTION_UP) imeKeyActive=false;
    }
    private void cancelImeKey() {
        if(!imeKeyActive || automation==null) return;
        try { sendImeKey(KeyEvent.ACTION_UP,true); } catch(Throwable ignored) { }
        imeKeyActive=false;
    }
    private void dismissIme(Bundle result) {
        stage="ime_window_policy";
        AccessibilityServiceInfo info=automation.getServiceInfo(); require(info!=null);
        info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        automation.setServiceInfo(info);
        imePhase="BEFORE_KEY";
        ImeObservation before=observeImeUntil(SystemClock.elapsedRealtime()+5000L);
        result.putBoolean("ime_was_visible",before.visible);
        result.putBoolean("ime_dismissed",false);
        if(!before.visible) { stage="ime_noop"; return; }
        // No general Back navigation: the fresh APP + visible IME + focused
        // editable field above are mandatory before this fixed key sequence.
        stage="ime_back_down"; sendImeKey(KeyEvent.ACTION_DOWN,false);
        stage="ime_back_up"; sendImeKey(KeyEvent.ACTION_UP,false);
        imePhase="AFTER_KEY";
        stage="ime_readback"; long end=SystemClock.elapsedRealtime()+5000L;
        while(SystemClock.elapsedRealtime()<end) {
            ImeObservation after=observeImeUntil(end);
            if(!after.visible) {
                imeSubstage="SAME_WINDOW_FOCUS";
                require(after.windowId==before.windowId && after.focus!=null && after.focus.equals(before.focus)
                    && after.focus.isFocused() && after.focus.isEditable() && after.focus.isVisibleToUser() && after.focus.isEnabled());
                result.putBoolean("ime_dismissed",true); return;
            }
            SystemClock.sleep(Math.max(0L,Math.min(100L,end-SystemClock.elapsedRealtime())));
        }
        stage="ime_readback"; throw new IllegalStateException();
    }

}
