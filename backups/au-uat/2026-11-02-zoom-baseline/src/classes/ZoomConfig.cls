/** Reads the single Zoom_Config__mdt record ("Default") that holds the Zoom credentials. */
public with sharing class ZoomConfig {
    @TestVisible private static Zoom_Config__mdt testOverride;

    public static Zoom_Config__mdt get() {
        if (testOverride != null) { return testOverride; }
        Zoom_Config__mdt c = Zoom_Config__mdt.getInstance('Default');
        return c == null ? new Zoom_Config__mdt() : c;
    }
}