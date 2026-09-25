package com.meowwatch.native_ui_observer;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.Process;
import android.os.SystemClock;
import android.util.Base64;
import android.util.Log;
import android.util.Xml;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import org.xmlpull.v1.XmlSerializer;

/** Read-only, self-targeted instrumentation; no Activity or application hooks. */
public final class SnapshotInstrumentation extends Instrumentation {
    private static final int MAX_NODES = 2048;
    private static final int MAX_DEPTH = 48;
    private static final int MAX_BYTES = 262144;
    private static final int MAX_ATTRIBUTE = 4096;
    private static final int MAX_ATTEMPTS = 16;
    private static final long CAPTURE_BUDGET_MS = 8000;
    private static final long RETRY_DELAY_MS = 500;
    private static final int MAX_STAGE_EVENTS = 128;
    private static final int MAX_DIAGNOSTIC_WINDOWS = 8;
    private static final long DIAGNOSTIC_BUDGET_MS = 150;
    private String nonce;
    private String expectedPackage;
    private boolean emptyExpectedAppShell;
    private int nodes;
    private int currentDepth = -1;
    private int currentIndex = -1;
    private int currentChildren = -1;
    private long deadline;
    private int captureAttempt;
    private int stageSequence;
    private int requestedServiceFlags;
    private int reportedServiceFlags;
    private int serviceCapabilities;
    private String rootDiagnostic;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        nonce = arguments == null ? null : arguments.getString("nonce");
        expectedPackage = arguments == null ? null : arguments.getString("expectedPackage");
        stage("on_create");
        start();
    }

    @Override
    public void onStart() {
        stage("on_start");
        StringBuilder attempts = new StringBuilder();
        try {
            if (nonce == null || !nonce.matches("[a-f0-9]{32}") || expectedPackage == null
                    || !expectedPackage.matches("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+")) {
                throw new IllegalArgumentException();
            }
            stage("automation_start");
            UiAutomation automation = getUiAutomation(
                UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
            stage("automation_ready");
            AccessibilityServiceInfo service = automation.getServiceInfo();
            service.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            // getWindows() is used only to diagnose a missing active root. The
            // flag must be set before the first root read to make that result
            // meaningful; it does not provide a fallback hierarchy.
            service.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
            service.flags &= ~AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
            requestedServiceFlags = service.flags;
            automation.setServiceInfo(service);
            AccessibilityServiceInfo reportedService = automation.getServiceInfo();
            reportedServiceFlags = reportedService.flags;
            serviceCapabilities = reportedService.getCapabilities();
            // Cold instrumentation/accessibility setup has its own host budget.
            // All hierarchy attempts still share this single eight-second limit.
            deadline = SystemClock.uptimeMillis() + CAPTURE_BUDGET_MS;
            stage("service_ready");
            for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
                captureAttempt = attempt;
                nodes = 0;
                emptyExpectedAppShell = true;
                currentDepth = currentIndex = currentChildren = -1;
                try {
                    Bundle result = snapshot(automation);
                    appendAttempt(attempts, "ok");
                    metadata(result, attempts);
                    stage("finish");
                    finish(Activity.RESULT_OK, result);
                    return;
                } catch (CaptureFailure error) {
                    stage("attempt_failed");
                    appendAttempt(attempts, error.reason);
                    if (error.reason.equals("root_missing") && rootDiagnostic == null) {
                        rootDiagnostic = diagnoseMissingRoot(automation);
                        // Publish the completed bounded probe before another
                        // framework root/refresh call can block final delivery.
                        stage("root_diagnostic", rootDiagnostic);
                    }
                    if (!error.retryable() || attempt == MAX_ATTEMPTS
                            || SystemClock.uptimeMillis() + RETRY_DELAY_MS >= deadline) {
                        fail(error.reason, attempts);
                        return;
                    }
                    // Keep this connection alive while Android publishes its new
                    // tree. Never await UI idleness or reuse any partial traversal.
                    SystemClock.sleep(RETRY_DELAY_MS);
                }
            }
        } catch (Exception error) {
            // Fixed classifications retain the kind of failure, never exception
            // messages, view text, resource IDs or arbitrary class names.
            String reason;
            if (error instanceof SecurityException) {
                reason = "native_security_exception";
            } else if (error instanceof IllegalStateException) {
                reason = "native_state_exception";
            } else if (error instanceof IllegalArgumentException) {
                reason = "native_argument_exception";
            } else if (error instanceof IOException) {
                reason = "serialization_io_exception";
            } else {
                reason = "native_exception";
            }
            appendAttempt(attempts, reason);
            fail(reason, attempts);
        }
    }

    private Bundle snapshot(UiAutomation automation) throws IOException {
        AccessibilityNodeInfo root = null;
        try {
            checkDeadline();
            stage("root_start");
            root = automation.getRootInActiveWindow();
            if (root == null) {
                throw new CaptureFailure("root_missing");
            }
            stage("root_ready");
            stage("refresh_start");
            if (!root.refresh()) {
                throw new CaptureFailure("root_refresh_failed");
            }
            stage("refresh_ready");
            if (!root.isVisibleToUser()) {
                throw new CaptureFailure("root_invisible");
            }
            long capturedAt = SystemClock.uptimeMillis();
            long captureStartedElapsed = SystemClock.elapsedRealtime();
            BoundedOutput output = new BoundedOutput();
            XmlSerializer serializer = Xml.newSerializer();
            serializer.setOutput(output, "UTF-8");
            serializer.startDocument("UTF-8", true);
            serializer.startTag(null, "hierarchy");
            stage("traverse_start");
            writeNode(serializer, root, 0, 0);
            serializer.endTag(null, "hierarchy");
            serializer.endDocument();
            serializer.flush();
            checkDeadline();
            stage("traverse_ready");
            if (emptyExpectedAppShell) {
                // Android can publish Flutter's native containers before its
                // virtual accessibility descendants. Keep the same connection
                // and reread; an empty shell is not evidence of a dismissed UI.
                throw new CaptureFailure("flutter_semantics_unavailable");
            }
            Bundle result = new Bundle();
            result.putString("observer_uptime_ms", Long.toString(capturedAt));
            result.putString("observer_capture_started_elapsed_ms", Long.toString(captureStartedElapsed));
            result.putString("observer_capture_completed_elapsed_ms", Long.toString(SystemClock.elapsedRealtime()));
            result.putString("observer_nodes", Integer.toString(nodes));
            result.putString("observer_xml", Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP));
            return result;
        } finally {
            if (root != null) {
                root.recycle();
            }
        }
    }

    private void metadata(Bundle result, StringBuilder attempts) {
        result.putString("observer_protocol", "4");
        result.putString("observer_nonce", nonce);
        result.putString("observer_attempts", attempts.toString());
    }

    private void fail(String reason, StringBuilder attempts) {
        Bundle result = new Bundle();
        metadata(result, attempts);
        result.putString("observer_uptime_ms", Long.toString(SystemClock.uptimeMillis()));
        result.putString("observer_error", reason);
        if (reason.equals("root_missing")) {
            result.putString("observer_root_diagnostic", rootDiagnostic == null
                ? diagnostic("budget", SystemClock.uptimeMillis(), captureAttempt, -1, false, "-")
                : rootDiagnostic);
        }
        stage("finish");
        finish(Activity.RESULT_CANCELED, result);
    }

    private String diagnoseMissingRoot(UiAutomation automation) {
        final long at = SystemClock.uptimeMillis();
        final int attempt = captureAttempt;
        final long allowance = Math.min(DIAGNOSTIC_BUDGET_MS, deadline - at - RETRY_DELAY_MS);
        if (allowance <= 0) {
            return diagnostic("budget", at, attempt, -1, false, "-");
        }
        final AtomicReference<String> result = new AtomicReference<>();
        final AtomicBoolean cancelled = new AtomicBoolean();
        final long probeDeadline = at + allowance;
        // Standalone compilation uses Android SDK stubs without the Java
        // lambda bootstrap method; keep this helper compatible with them.
        Thread worker = new Thread(new Runnable() {
            @Override
            public void run() {
                List<AccessibilityWindowInfo> windows = null;
                try {
                    if (cancelled.get() || SystemClock.uptimeMillis() >= probeDeadline) return;
                    windows = automation.getWindows();
                    if (cancelled.get() || SystemClock.uptimeMillis() >= probeDeadline) return;
                    if (windows == null || windows.size() > 64) {
                        result.set(diagnostic("unavailable", at, attempt, -1, false, "-"));
                        return;
                    }
                    int count = windows.size();
                    int limit = Math.min(count, MAX_DIAGNOSTIC_WINDOWS);
                    int[][] rows = new int[limit][6];
                    for (int i = 0; i < limit; i++) {
                        if (cancelled.get() || SystemClock.uptimeMillis() >= probeDeadline) return;
                        AccessibilityWindowInfo window = windows.get(i);
                        rows[i][0] = window.getId();
                        rows[i][1] = window.getType();
                        rows[i][2] = window.isActive() ? 1 : 0;
                        rows[i][3] = window.isFocused() ? 1 : 0;
                        rows[i][4] = 3; // Root query pending.
                    }
                    result.set(diagnosticWindows(limit == 0 ? "ok" : "partial", at, attempt, count, rows));
                    for (int i = 0; i < limit; i++) {
                        if (cancelled.get() || SystemClock.uptimeMillis() >= probeDeadline) return;
                        AccessibilityWindowInfo window = windows.get(i);
                        AccessibilityNodeInfo root = null;
                        int rootState = 0;
                        int packageMatch = 0;
                        try {
                            root = window.getRoot();
                            if (cancelled.get() || SystemClock.uptimeMillis() >= probeDeadline) return;
                            if (root != null) {
                                rootState = 1;
                                CharSequence name = root.getPackageName();
                                packageMatch = name == null ? 0
                                    : expectedPackage.contentEquals(name) ? 1 : 2;
                            }
                        } catch (RuntimeException ignored) {
                            rootState = 2;
                        } finally {
                            if (root != null) root.recycle();
                        }
                        if (cancelled.get() || SystemClock.uptimeMillis() >= probeDeadline) return;
                        rows[i][4] = rootState;
                        rows[i][5] = packageMatch;
                        result.set(diagnosticWindows(i + 1 == limit ? "ok" : "partial",
                            at, attempt, count, rows));
                    }
                    if (limit == 0) result.set(diagnosticWindows("ok", at, attempt, count, rows));
                } catch (RuntimeException ignored) {
                    if (result.get() == null) {
                        result.set(diagnostic("unavailable", at, attempt, -1, false, "-"));
                    }
                } finally {
                    if (windows != null) {
                        for (int i = 0; i < Math.min(windows.size(), 64); i++) {
                            windows.get(i).recycle();
                        }
                    }
                }
            }
        }, "root-missing-diagnostic");
        worker.setDaemon(true);
        worker.start();
        try {
            worker.join(allowance);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
        if (worker.isAlive()) {
            cancelled.set(true);
            worker.interrupt();
            String partial = result.get();
            return partial == null ? diagnostic("timeout", at, attempt, -1, false, "-") : partial;
        }
        String value = result.get();
        return value == null ? diagnostic("unavailable", at, attempt, -1, false, "-") : value;
    }

    private String diagnosticWindows(String status, long at, int attempt, int count, int[][] windows) {
        StringBuilder rows = new StringBuilder();
        for (int i = 0; i < windows.length; i++) {
            if (i > 0) rows.append(';');
            for (int j = 0; j < windows[i].length; j++) {
                if (j > 0) rows.append(':');
                rows.append(windows[i][j]);
            }
        }
        return diagnostic(status, at, attempt, count, count > MAX_DIAGNOSTIC_WINDOWS,
            rows.length() == 0 ? "-" : rows.toString());
    }

    private String diagnostic(String status, long at, int attempt, int count,
                              boolean truncated, String rows) {
        // Fixed numeric fields and enums only: no titles, view text, other
        // package names, resource IDs or arbitrary exception messages.
        return "1|" + at + "|" + attempt + "|" + requestedServiceFlags + "|"
            + reportedServiceFlags + "|" + serviceCapabilities + "|" + status + "|"
            + count + "|" + (truncated ? 1 : 0) + "|" + rows;
    }

    private void stage(String name) {
        stage(name, null);
    }

    private void stage(String name, String diagnostic) {
        if (nonce == null || !nonce.matches("[a-f0-9]{32}") || stageSequence >= MAX_STAGE_EVENTS) {
            return;
        }
        // Only fixed call-site names and bounded structural numbers are sent.
        // No view contents, resource IDs, window names or exception text.
        String value = nonce + ":" + Process.myPid() + ":" + (++stageSequence) + ":" + name
            + ":" + SystemClock.uptimeMillis() + ":" + captureAttempt
            + ":" + Math.min(nodes, MAX_NODES + 1);
        if (diagnostic != null) value += ":" + diagnostic;
        Log.i("MWNativeUiStage", value);
        Bundle progress = new Bundle();
        progress.putString("observer_stage", value);
        try {
            // Status is streamed before the final XML result, so the host can
            // retain completed stages even if its unchanged watchdog expires.
            sendStatus(2, progress);
        } catch (RuntimeException ignored) {
            // A timed-out watcher may already be gone. Logcat retains the same
            // fixed diagnostic; this must not change the capture's outcome.
        }
    }

    private void appendAttempt(StringBuilder attempts, String reason) {
        if (attempts.length() > 0) {
            attempts.append(';');
        }
        attempts.append(reason).append(':').append(nodes).append(':').append(currentDepth)
            .append(':').append(currentIndex).append(':').append(currentChildren);
    }

    private void checkDeadline() {
        if (SystemClock.uptimeMillis() >= deadline) {
            throw new CaptureFailure("capture_deadline");
        }
    }

    private void writeNode(XmlSerializer xml, AccessibilityNodeInfo node, int index, int depth)
            throws IOException {
        currentDepth = depth;
        currentIndex = index;
        currentChildren = -1;
        checkDeadline();
        if (++nodes > MAX_NODES) {
            throw new CaptureFailure("node_limit");
        }
        if (depth > MAX_DEPTH) {
            throw new CaptureFailure("depth_limit");
        }
        emptyExpectedAppShell &= expectedPackage.contentEquals(
            node.getPackageName() == null ? "" : node.getPackageName())
            && "android.widget.FrameLayout".contentEquals(
                node.getClassName() == null ? "" : node.getClassName())
            && empty(node.getText()) && empty(node.getContentDescription())
            && empty(node.getViewIdResourceName()) && !node.isClickable()
            && !node.isLongClickable() && !node.isScrollable() && !node.isCheckable();
        xml.startTag(null, "node");
        attribute(xml, "index", Integer.toString(index));
        attribute(xml, "text", node.getText());
        attribute(xml, "resource-id", node.getViewIdResourceName());
        attribute(xml, "class", node.getClassName());
        attribute(xml, "package", node.getPackageName());
        attribute(xml, "content-desc", node.getContentDescription());
        attribute(xml, "checkable", Boolean.toString(node.isCheckable()));
        attribute(xml, "checked", Boolean.toString(node.isChecked()));
        attribute(xml, "clickable", Boolean.toString(node.isClickable()));
        attribute(xml, "enabled", Boolean.toString(node.isEnabled()));
        attribute(xml, "focusable", Boolean.toString(node.isFocusable()));
        attribute(xml, "focused", Boolean.toString(node.isFocused()));
        attribute(xml, "scrollable", Boolean.toString(node.isScrollable()));
        attribute(xml, "long-clickable", Boolean.toString(node.isLongClickable()));
        attribute(xml, "password", Boolean.toString(node.isPassword()));
        attribute(xml, "selected", Boolean.toString(node.isSelected()));
        attribute(xml, "visible-to-user", Boolean.toString(node.isVisibleToUser()));
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        attribute(xml, "bounds", "[" + bounds.left + "," + bounds.top + "]["
            + bounds.right + "," + bounds.bottom + "]");
        int children = node.getChildCount();
        currentChildren = Math.min(children, MAX_NODES + 1);
        if (children > MAX_NODES - nodes) {
            throw new CaptureFailure("child_count_limit");
        }
        for (int i = 0; i < children; i++) {
            currentDepth = depth + 1;
            currentIndex = i;
            currentChildren = children;
            checkDeadline();
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) {
                throw new CaptureFailure("child_missing");
            }
            try {
                if (child.isVisibleToUser()) {
                    writeNode(xml, child, i, depth + 1);
                }
            } finally {
                child.recycle();
            }
        }
        xml.endTag(null, "node");
    }

    private static void attribute(XmlSerializer xml, String name, CharSequence value)
            throws IOException {
        String text = value == null ? "" : value.toString();
        if (text.length() > MAX_ATTRIBUTE) {
            throw new CaptureFailure("attribute_limit");
        }
        xml.attribute(null, name, text);
    }

    private static boolean empty(CharSequence value) {
        return value == null || value.length() == 0;
    }

    private static final class CaptureFailure extends RuntimeException {
        final String reason;

        CaptureFailure(String reason) {
            this.reason = reason;
        }

        boolean retryable() {
            return reason.equals("root_missing") || reason.equals("root_refresh_failed")
                || reason.equals("root_invisible") || reason.equals("child_missing")
                || reason.equals("flutter_semantics_unavailable");
        }
    }

    private static final class BoundedOutput extends ByteArrayOutputStream {
        @Override
        public synchronized void write(int value) {
            if (count >= MAX_BYTES) {
                throw new CaptureFailure("byte_limit");
            }
            super.write(value);
        }

        @Override
        public synchronized void write(byte[] buffer, int offset, int length) {
            if (length > MAX_BYTES - count) {
                throw new CaptureFailure("byte_limit");
            }
            super.write(buffer, offset, length);
        }
    }
}
