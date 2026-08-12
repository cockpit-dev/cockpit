package dev.cockpit.driver;

import static org.junit.Assert.assertTrue;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Xml;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.xmlpull.v1.XmlSerializer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

@RunWith(AndroidJUnit4.class)
public final class CockpitDriverTest {
    private static final String[] ACCEPT_DIALOG_IDS = {
            "android:id/aerr_wait",
            "com.android.permissioncontroller:id/permission_allow_button",
            "com.android.permissioncontroller:id/permission_allow_foreground_only_button",
            "com.android.permissioncontroller:id/permission_allow_one_time_button",
            "com.android.permissioncontroller:id/permission_allow_always_button",
            "com.google.android.permissioncontroller:id/permission_allow_button",
            "com.google.android.permissioncontroller:id/permission_allow_foreground_only_button",
            "com.google.android.permissioncontroller:id/permission_allow_one_time_button",
            "com.android.packageinstaller:id/permission_allow_button",
            "android:id/button1"
    };
    private static final String[] DISMISS_DIALOG_IDS = {
            "android:id/aerr_close",
            "com.android.permissioncontroller:id/permission_deny_button",
            "com.android.permissioncontroller:id/permission_deny_and_dont_ask_again_button",
            "com.google.android.permissioncontroller:id/permission_deny_button",
            "com.google.android.permissioncontroller:id/permission_deny_and_dont_ask_again_button",
            "com.android.packageinstaller:id/permission_deny_button",
            "android:id/button2"
    };
    private static final String[] ACCEPT_DIALOG_TEXT = {
            "Wait", "Allow", "ALLOW", "While using the app", "Only this time", "OK"
    };
    private static final String[] DISMISS_DIALOG_TEXT = {
            "Close app", "Deny", "DENY", "Don't allow", "Don\u2019t allow", "Cancel", "CANCEL"
    };

    @Test
    public void dumpUiTree() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        UiAutomation automation = configuredAutomation(instrumentation);

        Bundle arguments = InstrumentationRegistry.getArguments();
        int maxDepth = boundedInteger(arguments.getString("maxDepth"), 16, 1, 64);
        int maxNodes = boundedInteger(arguments.getString("maxNodes"), 2000, 1, 10000);
        List<AccessibilityNodeInfo> roots = roots(automation);
        File output = new File(instrumentation.getTargetContext().getFilesDir(), "window.xml");
        int count;
        try (OutputStream stream = new FileOutputStream(output, false)) {
            count = writeHierarchy(stream, roots, maxDepth, maxNodes);
        }
        assertTrue("No accessible UI roots were returned", count > 0);
    }

    @Test
    public void tapSystemDialog() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        UiAutomation automation = configuredAutomation(instrumentation);
        String decision = InstrumentationRegistry.getArguments().getString("decision", "accept");
        boolean dismiss = "dismiss".equals(decision);
        AccessibilityNodeInfo match = waitForMatch(
                automation,
                dismiss ? DISMISS_DIALOG_IDS : ACCEPT_DIALOG_IDS,
                dismiss ? DISMISS_DIALOG_TEXT : ACCEPT_DIALOG_TEXT,
                false,
                1000
        );
        boolean handled = match != null && click(match);
        Bundle result = new Bundle();
        result.putString("cockpitHandled", Boolean.toString(handled));
        instrumentation.sendStatus(0, result);
    }

    @Test
    public void tapNotification() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        UiAutomation automation = configuredAutomation(instrumentation);
        String text = InstrumentationRegistry.getArguments().getString("text", "").trim();
        assertTrue("Notification text is required", !text.isEmpty());
        AccessibilityNodeInfo match = waitForMatch(
                automation,
                new String[0],
                new String[]{text},
                true,
                3000
        );
        assertTrue("No matching Android notification was available", match != null && click(match));
    }

    private static UiAutomation configuredAutomation(Instrumentation instrumentation) throws Exception {
        UiAutomation automation = instrumentation.getUiAutomation();
        AccessibilityServiceInfo serviceInfo = automation.getServiceInfo();
        serviceInfo.flags |= AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        automation.setServiceInfo(serviceInfo);
        automation.waitForIdle(200, 3000);
        return automation;
    }

    private static List<AccessibilityNodeInfo> roots(UiAutomation automation) {
        List<AccessibilityNodeInfo> roots = new ArrayList<>();
        for (AccessibilityWindowInfo window : automation.getWindows()) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root != null) {
                roots.add(root);
            }
        }
        if (roots.isEmpty()) {
            AccessibilityNodeInfo root = automation.getRootInActiveWindow();
            if (root != null) {
                roots.add(root);
            }
        }
        return roots;
    }

    private static AccessibilityNodeInfo findBestMatch(
            List<AccessibilityNodeInfo> roots,
            String[] resourceIds,
            String[] texts,
            boolean containsText
    ) {
        List<AccessibilityNodeInfo> nodes = new ArrayList<>();
        for (AccessibilityNodeInfo root : roots) {
            collectNodes(root, nodes, 10000);
        }
        for (String resourceId : resourceIds) {
            for (AccessibilityNodeInfo node : nodes) {
                if (node.isVisibleToUser()
                        && node.isEnabled()
                        && resourceId.equals(node.getViewIdResourceName())) {
                    return node;
                }
            }
        }
        for (String text : texts) {
            for (AccessibilityNodeInfo node : nodes) {
                if (!node.isVisibleToUser() || !node.isEnabled() || !isSystemNode(node)) {
                    continue;
                }
                if (matches(node.getText(), text, containsText)
                        || matches(node.getContentDescription(), text, containsText)) {
                    return node;
                }
            }
        }
        return null;
    }

    private static AccessibilityNodeInfo waitForMatch(
            UiAutomation automation,
            String[] resourceIds,
            String[] texts,
            boolean containsText,
            long timeoutMillis
    ) {
        long deadline = SystemClock.elapsedRealtime() + timeoutMillis;
        do {
            AccessibilityNodeInfo match = findBestMatch(
                    roots(automation),
                    resourceIds,
                    texts,
                    containsText
            );
            if (match != null) {
                return match;
            }
            SystemClock.sleep(100);
        } while (SystemClock.elapsedRealtime() < deadline);
        return null;
    }

    private static void collectNodes(
            AccessibilityNodeInfo node,
            List<AccessibilityNodeInfo> nodes,
            int maximum
    ) {
        if (nodes.size() >= maximum) {
            return;
        }
        nodes.add(node);
        for (int index = 0; index < node.getChildCount() && nodes.size() < maximum; index++) {
            AccessibilityNodeInfo child = node.getChild(index);
            if (child != null) {
                collectNodes(child, nodes, maximum);
            }
        }
    }

    private static boolean isSystemNode(AccessibilityNodeInfo node) {
        CharSequence rawPackage = node.getPackageName();
        if (rawPackage == null) {
            return false;
        }
        String packageName = rawPackage.toString();
        return "android".equals(packageName)
                || packageName.startsWith("com.android.")
                || packageName.startsWith("com.google.android.")
                || packageName.contains("permissioncontroller")
                || packageName.contains("packageinstaller")
                || packageName.contains("systemui");
    }

    private static boolean matches(CharSequence value, String expected, boolean contains) {
        if (value == null) {
            return false;
        }
        String actual = value.toString();
        return contains ? actual.contains(expected) : actual.equals(expected);
    }

    private static boolean click(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo candidate = node;
        while (candidate != null) {
            if (candidate.isEnabled()
                    && candidate.isClickable()
                    && candidate.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true;
            }
            candidate = candidate.getParent();
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }

    private static int writeHierarchy(
            OutputStream output,
            List<AccessibilityNodeInfo> roots,
            int maxDepth,
            int maxNodes
    ) throws Exception {
        XmlSerializer serializer = Xml.newSerializer();
        serializer.setOutput(output, "UTF-8");
        serializer.startDocument("UTF-8", true);
        serializer.startTag("", "hierarchy");
        NodeBudget budget = new NodeBudget(maxNodes);
        int index = 0;
        for (AccessibilityNodeInfo root : roots) {
            if (!budget.available()) {
                break;
            }
            writeNode(serializer, root, index++, 0, maxDepth, budget);
        }
        serializer.endTag("", "hierarchy");
        serializer.endDocument();
        return budget.used();
    }

    private static void writeNode(
            XmlSerializer serializer,
            AccessibilityNodeInfo node,
            int index,
            int depth,
            int maxDepth,
            NodeBudget budget
    ) throws Exception {
        if (!budget.take()) {
            return;
        }
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        serializer.startTag("", "node");
        attribute(serializer, "index", Integer.toString(index));
        attribute(serializer, "text", node.getText());
        attribute(serializer, "resource-id", node.getViewIdResourceName());
        attribute(serializer, "class", node.getClassName());
        attribute(serializer, "package", node.getPackageName());
        attribute(serializer, "content-desc", node.getContentDescription());
        attribute(serializer, "hintText", node.getHintText());
        attribute(serializer, "checkable", node.isCheckable());
        attribute(serializer, "checked", node.isChecked());
        attribute(serializer, "clickable", node.isClickable());
        attribute(serializer, "enabled", node.isEnabled());
        attribute(serializer, "focusable", node.isFocusable());
        attribute(serializer, "focused", node.isFocused());
        attribute(serializer, "scrollable", node.isScrollable());
        attribute(serializer, "long-clickable", node.isLongClickable());
        // "password=" is treated as an inline credential by the Supervisor.
        // Keep the boolean state without making the serialized XML ambiguous.
        attribute(serializer, "secure", node.isPassword());
        attribute(serializer, "selected", node.isSelected());
        attribute(serializer, "visible-to-user", node.isVisibleToUser());
        attribute(serializer, "bounds", bounds.toShortString());
        if (depth < maxDepth) {
            for (int childIndex = 0; childIndex < node.getChildCount(); childIndex++) {
                if (!budget.available()) {
                    break;
                }
                AccessibilityNodeInfo child = node.getChild(childIndex);
                if (child != null) {
                    writeNode(serializer, child, childIndex, depth + 1, maxDepth, budget);
                }
            }
        }
        serializer.endTag("", "node");
    }

    private static void attribute(XmlSerializer serializer, String name, Object value)
            throws Exception {
        serializer.attribute("", name, value == null ? "" : value.toString());
    }

    private static int boundedInteger(String raw, int fallback, int minimum, int maximum) {
        if (raw == null) {
            return fallback;
        }
        try {
            return Math.max(minimum, Math.min(maximum, Integer.parseInt(raw)));
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static final class NodeBudget {
        private final int maximum;
        private int used;

        private NodeBudget(int maximum) {
            this.maximum = maximum;
        }

        private boolean take() {
            if (!available()) {
                return false;
            }
            used++;
            return true;
        }

        private boolean available() {
            return used < maximum;
        }

        private int used() {
            return used;
        }
    }
}
