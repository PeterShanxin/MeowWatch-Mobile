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
    private String nonce;
    private int nodes;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        nonce = arguments == null ? null : arguments.getString("nonce");
        start();
    }

    @Override
    public void onStart() {
        Bundle result = new Bundle();
        AccessibilityNodeInfo root = null;
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
            // Playback changes accessibility values every 100 ms. A quiet-window
            // wait would starve. Read the active window directly and fail closed
            // if a complete, refreshed tree cannot be captured.
            root = automation.getRootInActiveWindow();
            if (root == null || !root.refresh() || !root.isVisibleToUser()) {
                result.putString("observer_error", "root_unavailable");
                finish(Activity.RESULT_CANCELED, result);
                return;
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
            result.putString("observer_protocol", "1");
            result.putString("observer_nonce", nonce);
            result.putString("observer_uptime_ms", Long.toString(capturedAt));
            result.putString("observer_nodes", Integer.toString(nodes));
            result.putString("observer_xml", Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP));
            finish(Activity.RESULT_OK, result);
        } catch (Exception error) {
            // Exception text can contain visible UI data. Return only a fixed code.
            result.clear();
            result.putString("observer_error", "snapshot_failed");
            finish(Activity.RESULT_CANCELED, result);
        } finally {
            if (root != null) {
                root.recycle();
            }
        }
    }

    private void writeNode(XmlSerializer xml, AccessibilityNodeInfo node, int index, int depth)
            throws IOException {
        if (++nodes > MAX_NODES || depth > MAX_DEPTH) {
            throw new IllegalStateException();
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
        if (children > MAX_NODES - nodes) {
            throw new IllegalStateException();
        }
        for (int i = 0; i < children; i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) {
                throw new IllegalStateException();
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
            throw new IllegalStateException();
        }
        xml.attribute(null, name, text);
    }

    private static final class BoundedOutput extends ByteArrayOutputStream {
        @Override
        public synchronized void write(int value) {
            if (count >= MAX_BYTES) {
                throw new IllegalStateException();
            }
            super.write(value);
        }

        @Override
        public synchronized void write(byte[] buffer, int offset, int length) {
            if (length > MAX_BYTES - count) {
                throw new IllegalStateException();
            }
            super.write(buffer, offset, length);
        }
    }
}
