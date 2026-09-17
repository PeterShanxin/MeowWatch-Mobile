package com.meowwatch.native_ui_observer;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Base64;
import android.util.Xml;
import android.view.accessibility.AccessibilityNodeInfo;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import org.xmlpull.v1.XmlSerializer;

/** Read-only, self-targeted instrumentation; no Activity or application hooks. */
public final class SnapshotInstrumentation extends Instrumentation {
    private static final int MAX_NODES = 2048;
    private static final int MAX_DEPTH = 48;
    private static final int MAX_BYTES = 262144;
    private static final int MAX_ATTRIBUTE = 4096;
    private static final int MAX_ATTEMPTS = 4;
    private static final long CAPTURE_BUDGET_MS = 4000;
    private static final long RETRY_DELAY_MS = 100;
    private String nonce;
    private int nodes;
    private int currentDepth = -1;
    private int currentIndex = -1;
    private int currentChildren = -1;
    private long deadline;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        nonce = arguments == null ? null : arguments.getString("nonce");
        start();
    }

    @Override
    public void onStart() {
        deadline = SystemClock.uptimeMillis() + CAPTURE_BUDGET_MS;
        StringBuilder attempts = new StringBuilder();
        try {
            if (nonce == null || !nonce.matches("[a-f0-9]{32}")) {
                throw new IllegalArgumentException();
            }
            UiAutomation automation = getUiAutomation(
                UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
            AccessibilityServiceInfo service = automation.getServiceInfo();
            service.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            service.flags &= ~AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
            automation.setServiceInfo(service);
            for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
                nodes = 0;
                currentDepth = currentIndex = currentChildren = -1;
                try {
                    Bundle result = snapshot(automation);
                    appendAttempt(attempts, "ok");
                    metadata(result, attempts);
                    finish(Activity.RESULT_OK, result);
                    return;
                } catch (CaptureFailure error) {
                    appendAttempt(attempts, error.reason);
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
            root = automation.getRootInActiveWindow();
            if (root == null) {
                throw new CaptureFailure("root_missing");
            }
            if (!root.refresh()) {
                throw new CaptureFailure("root_refresh_failed");
            }
            if (!root.isVisibleToUser()) {
                throw new CaptureFailure("root_invisible");
            }
            long capturedAt = SystemClock.uptimeMillis();
            BoundedOutput output = new BoundedOutput();
            XmlSerializer serializer = Xml.newSerializer();
            serializer.setOutput(output, "UTF-8");
            serializer.startDocument("UTF-8", true);
            serializer.startTag(null, "hierarchy");
            writeNode(serializer, root, 0, 0);
            serializer.endTag(null, "hierarchy");
            serializer.endDocument();
            serializer.flush();
            checkDeadline();
            Bundle result = new Bundle();
            result.putString("observer_uptime_ms", Long.toString(capturedAt));
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
        result.putString("observer_protocol", "2");
        result.putString("observer_nonce", nonce);
        result.putString("observer_attempts", attempts.toString());
    }

    private void fail(String reason, StringBuilder attempts) {
        Bundle result = new Bundle();
        metadata(result, attempts);
        result.putString("observer_uptime_ms", Long.toString(SystemClock.uptimeMillis()));
        result.putString("observer_error", reason);
        finish(Activity.RESULT_CANCELED, result);
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

    private static final class CaptureFailure extends RuntimeException {
        final String reason;

        CaptureFailure(String reason) {
            this.reason = reason;
        }

        boolean retryable() {
            return reason.equals("root_missing") || reason.equals("root_refresh_failed")
                || reason.equals("root_invisible") || reason.equals("child_missing");
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
