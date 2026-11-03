package com.aqer.phase1.input;

import android.app.Instrumentation;
import android.app.UiAutomation;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import java.util.ArrayList;
import java.util.List;

/** Disposable test-only input. No Activity, network, credentials or shell identity. */
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

    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); args = arguments; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        String op = args == null ? "" : args.getString("op", "");
        try {
            require(Build.VERSION.SDK_INT == 36 && ("ranchu".equals(Build.HARDWARE) || "goldfish".equals(Build.HARDWARE)));
            stage="automation"; automation = getUiAutomation();
            origin = SystemClock.uptimeMillis();
            AccessibilityNodeInfo root = readyRoot(op); stage="root_ready";
            if ("submit-query".equals(op)) {
                require(!contains(root,"شروط البحث"));
                List<AccessibilityNodeInfo> controls=new ArrayList<>();
                namedClickable(root,"تنفيذ",controls); require(controls.size()==1);
                stage="submit_action";
                require(controls.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK));
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
                require(fields.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK));
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
                stage="query_action"; require(field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, value));
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
            stage="complete"; result.putString("op", op);
            result.putBoolean("passed", true);
            finish(-1, result);
        } catch (Throwable failure) {
            cancelPointer();
            // Never return arbitrary exception text, accessibility content or stack traces.
            result.putString("op", safeOp(op));
            result.putBoolean("passed", false);
            result.putInt("events", events);
            result.putString("stage", stage);
            result.putString("event_ms", numbers(eventTimes));
            result.putString("return_ms", numbers(returnTimes));
            result.putString("reason", "input_precondition_or_delivery_failed");
            finish(0, result);
        }
    }
    private AccessibilityNodeInfo readyRoot(String op) {
        long deadline=SystemClock.uptimeMillis()+5000;
        while(SystemClock.uptimeMillis()<deadline) {
            AccessibilityNodeInfo root=automation.getRootInActiveWindow();
            if(root!=null && root.getPackageName()!=null && APP.contentEquals(root.getPackageName())) {
                boolean query="fixture-query".equals(op)||"negative-query".equals(op)||"clear-query".equals(op)||"submit-query".equals(op);
                if(query ? contains(root,"البحث عن عقار")||contains(root,"البحث على الخريطة")
                         : contains(root,"صورة العقار 1 من 1")&&contains(root,"1/1")) return root;
            }
            SystemClock.sleep(100);
        }
        throw new IllegalStateException();
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
        return "fixture-query".equals(op) || "negative-query".equals(op) || "clear-query".equals(op) || "submit-query".equals(op) || "double-tap".equals(op)
            || "pinch-in".equals(op) || "pinch-out".equals(op) ? op : "invalid";
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
        if(!ending) pointerActive=true;
        MotionEvent event=MotionEvent.obtain(down,when,action,xs.length,properties,coords,0,0,1,1,0,0,InputDevice.SOURCE_TOUCHSCREEN,0);
        try {
            require(automation.injectInputEvent(event,true)); events++;
            if(ending) pointerActive=false;
            eventTimes.add(when-origin); returnTimes.add(SystemClock.uptimeMillis()-origin);
        } finally { event.recycle(); }
        return when;
    }
}
