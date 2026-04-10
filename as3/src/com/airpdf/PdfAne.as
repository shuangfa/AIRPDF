package com.airpdf {

import flash.display.BitmapData;
import flash.external.ExtensionContext;
import flash.system.Capabilities;

/**
 * Windows-x86 ANE: open a PDF path, query page count, render a page into a BitmapData.
 * Without native PDFium build, the DLL renders a placeholder pattern (same API).
 */
public class PdfAne {

    public static const EXTENSION_ID:String = "com.airpdf.PdfAne";

    private static var _ctx:ExtensionContext;

    private static function ctx():ExtensionContext {
        if (!_ctx) {
            _ctx = ExtensionContext.createExtensionContext(EXTENSION_ID, null);
        }
        return _ctx;
    }

    /** True when running on supported Win32 AIR (ANE packaged for Windows-x86). */
    public static function get isSupported():Boolean {
        if (Capabilities.os.indexOf("Windows") < 0) {
            return false;
        }
        var c:ExtensionContext = ExtensionContext.createExtensionContext(EXTENSION_ID, null);
        if (c) {
            c.dispose();
            return true;
        }
        return false;
    }

    public static function open(path:String):Boolean {
        return ctx().call("open", path) === true;
    }

    public static function close():void {
        if (_ctx) {
            _ctx.call("close");
        }
    }

    public static function getPageCount():int {
        return int(ctx().call("getPageCount"));
    }

    /** Renders pageIndex into target (replaces pixels). Target should be transparent=false for PDF. */
    public static function renderPage(pageIndex:int, target:BitmapData):Boolean {
        return ctx().call("renderPage", pageIndex, target) === true;
    }

    public static function getLastError():String {
        var s:Object = ctx().call("getLastError");
        return s == null ? "" : String(s);
    }

    /** "pdfium" = real raster; "placeholder" = checkerboard stub (no PDFium in DLL). */
    public static function getRenderer():String {
        var s:Object = ctx().call("getRenderer");
        return s == null ? "" : String(s);
    }

    public static function dispose():void {
        close();
        if (_ctx) {
            _ctx.dispose();
            _ctx = null;
        }
    }
}
}
