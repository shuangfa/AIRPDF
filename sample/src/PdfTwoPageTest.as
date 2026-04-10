package {

import com.airpdf.PdfAne;

import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.Sprite;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.filesystem.File;
import flash.net.FileFilter;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFormat;

/**
 * Test: open a PDF via PdfAne, show two pages side by side (spread).
 * Prev / Next moves by pairs (0–1, 2–3, …). Requires 32-bit AIR + Windows-x86 ANE.
 */
public class PdfTwoPageTest extends Sprite {

    private static const PAGE_W:int = 440;
    private static const PAGE_H:int = 620;
    private static const GAP:int = 16;

    private var _fmt:TextFormat;
    private var _status:TextField;
    private var _leftBd:BitmapData;
    private var _rightBd:BitmapData;
    private var _leftBm:Bitmap;
    private var _rightBm:Bitmap;
    private var _pageCount:int;
    private var _pairStart:int;
    private var _btnOpen:Sprite;
    private var _btnPrev:Sprite;
    private var _btnNext:Sprite;

    public function PdfTwoPageTest() {
        _fmt = new TextFormat("_sans", 12, 0x101010);
        _pageCount = 0;
        _pairStart = 0;
        addEventListener(Event.ADDED_TO_STAGE, onStage);
    }

    private function onStage(e:Event):void {
        removeEventListener(Event.ADDED_TO_STAGE, onStage);
        stage.align = StageAlign.TOP_LEFT;
        stage.scaleMode = StageScaleMode.NO_SCALE;
        stage.color = 0x444444;

        if (!PdfAne.isSupported) {
            addChild(makeLabel("PdfAne 未加载：请用 32 位 Windows AIR + extendedDesktop，并把 PdfAne.ane 放到 adl 的 -extdir 目录。", 16, 16, 900, 0xFFFFFF));
            return;
        }

        _leftBd = new BitmapData(PAGE_W, PAGE_H, false, 0xFFCCCCCC);
        _rightBd = new BitmapData(PAGE_W, PAGE_H, false, 0xFFCCCCCC);
        _leftBm = new Bitmap(_leftBd);
        _rightBm = new Bitmap(_rightBd);
        _leftBm.x = 20;
        _leftBm.y = 52;
        _rightBm.x = _leftBm.x + PAGE_W + GAP;
        _rightBm.y = _leftBm.y;
        addChild(_leftBm);
        addChild(_rightBm);

        var engine:String = PdfAne.getRenderer();
        var hint:String = engine == "pdfium"
            ? "引擎: pdfium（真实 PDF 位图）"
            : "引擎: placeholder — 当前为棋盘格占位。要真实画面：在项目根目录运行 fetch-pdfium.bat，再运行 build.bat（或 build-pdfium.bat），把 bin\\PdfAne.ane 拷到 sample\\ext 后重编示例。";
        _status = makeLabel(hint + "\n点击「打开 PDF」", 20, 12, 920, 0xEEEEEE);
        addChild(_status);

        _btnOpen = makeButton("打开 PDF", 20, _leftBm.y + PAGE_H + 16);
        _btnPrev = makeButton("上一对", 140, _btnOpen.y);
        _btnNext = makeButton("下一对", 260, _btnOpen.y);
        _btnOpen.addEventListener(MouseEvent.CLICK, onOpenClick);
        _btnPrev.addEventListener(MouseEvent.CLICK, onPrevClick);
        _btnNext.addEventListener(MouseEvent.CLICK, onNextClick);
        addChild(_btnOpen);
        addChild(_btnPrev);
        addChild(_btnNext);

        updateNavEnabled();
        stage.addEventListener(Event.RESIZE, onResize);
        layoutChrome();
    }

    private function onResize(e:Event = null):void {
        layoutChrome();
    }

    private function layoutChrome():void {
        if (!stage) {
            return;
        }
        var w:Number = stage.stageWidth;
        var h:Number = stage.stageHeight;
        var totalW:Number = PAGE_W * 2 + GAP;
        var baseX:Number = Math.max(12, (w - totalW) * 0.5);
        _leftBm.x = baseX;
        _rightBm.x = baseX + PAGE_W + GAP;
        _leftBm.y = Math.min(52, Math.max(40, (h - PAGE_H) * 0.35));
        _rightBm.y = _leftBm.y;
        if (_btnOpen) {
            _btnOpen.y = _leftBm.y + PAGE_H + 16;
            _btnPrev.y = _btnOpen.y;
            _btnNext.y = _btnOpen.y;
            _btnOpen.x = baseX;
            _btnPrev.x = baseX + 120;
            _btnNext.x = baseX + 240;
        }
        if (_status) {
            _status.x = baseX;
        }
    }

    private function makeLabel(txt:String, xx:Number, yy:Number, wMax:Number, col:uint):TextField {
        var tf:TextField = new TextField();
        tf.defaultTextFormat = new TextFormat("_sans", 12, col);
        tf.text = txt;
        tf.x = xx;
        tf.y = yy;
        tf.width = wMax;
        tf.height = 200;
        tf.wordWrap = true;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function makeButton(caption:String, xx:Number, yy:Number):Sprite {
        var s:Sprite = new Sprite();
        var tf:TextField = new TextField();
        tf.autoSize = TextFieldAutoSize.LEFT;
        tf.defaultTextFormat = _fmt;
        tf.text = caption;
        tf.selectable = false;
        tf.x = 10;
        tf.y = 6;
        var bw:Number = Math.max(96, tf.textWidth + 24);
        var bh:Number = 32;
        s.graphics.beginFill(0xDDDDDD);
        s.graphics.drawRoundRect(0, 0, bw, bh, 6, 6);
        s.graphics.endFill();
        s.graphics.lineStyle(1, 0x888888);
        s.graphics.drawRoundRect(0, 0, bw, bh, 6, 6);
        s.addChild(tf);
        s.buttonMode = true;
        s.mouseChildren = false;
        s.x = xx;
        s.y = yy;
        return s;
    }

    private function setStatus(msg:String):void {
        if (_status) {
            _status.text = msg;
        }
    }

    private function onOpenClick(e:MouseEvent):void {
        var f:File = new File();
        f.addEventListener(Event.SELECT, onFileSelected);
        f.browseForOpen("选择 PDF", [new FileFilter("PDF", "*.pdf")]);
    }

    private function onFileSelected(e:Event):void {
        var f:File = e.target as File;
        if (!f) {
            return;
        }
        PdfAne.close();
        if (!PdfAne.open(f.nativePath)) {
            setStatus("打开失败: " + PdfAne.getLastError());
            _pageCount = 0;
            updateNavEnabled();
            return;
        }
        _pageCount = PdfAne.getPageCount();
        _pairStart = 0;
        renderCurrentPair();
        updateNavEnabled();
    }

    private function onPrevClick(e:MouseEvent):void {
        if (_pairStart >= 2) {
            _pairStart -= 2;
        } else {
            _pairStart = 0;
        }
        renderCurrentPair();
        updateNavEnabled();
    }

    private function onNextClick(e:MouseEvent):void {
        if (_pairStart + 2 < _pageCount) {
            _pairStart += 2;
        }
        renderCurrentPair();
        updateNavEnabled();
    }

    private function updateNavEnabled():void {
        if (!_btnPrev || !_btnNext) {
            return;
        }
        _btnPrev.alpha = _pageCount > 0 && _pairStart > 0 ? 1 : 0.45;
        _btnNext.alpha = _pageCount > 0 && _pairStart + 2 < _pageCount ? 1 : 0.45;
        _btnPrev.mouseEnabled = _pageCount > 0 && _pairStart > 0;
        _btnNext.mouseEnabled = _pageCount > 0 && _pairStart + 2 < _pageCount;
    }

    private function renderCurrentPair():void {
        if (!_leftBd || !_rightBd || _pageCount <= 0) {
            return;
        }

        var i0:int = _pairStart;
        var i1:int = _pairStart + 1;

        if (!PdfAne.renderPage(i0, _leftBd)) {
            _leftBd.fillRect(_leftBd.rect, 0xFFFFAAAA);
            setStatus("左页渲染失败: " + PdfAne.getLastError());
        }

        if (i1 < _pageCount) {
            if (!PdfAne.renderPage(i1, _rightBd)) {
                _rightBd.fillRect(_rightBd.rect, 0xFFFFAAAA);
                setStatus("右页渲染失败: " + PdfAne.getLastError());
            }
        } else {
            _rightBd.fillRect(_rightBd.rect, 0xFFE8E8E8);
            drawRightPlaceholder();
        }

        var endP:int = Math.min(_pairStart + 2, _pageCount);
        setStatus(
            "当前展开: 第 " + (_pairStart + 1) + "–" + endP + " 页 / 共 " + _pageCount + " 页"
        );
    }

    private function drawRightPlaceholder():void {
        var tf:TextField = new TextField();
        tf.defaultTextFormat = new TextFormat("_sans", 18, 0x666666);
        tf.text = "（无右页\n奇数页末）";
        tf.x = PAGE_W * 0.5 - 70;
        tf.y = PAGE_H * 0.5 - 30;
        tf.width = 200;
        tf.height = 80;
        _rightBd.draw(tf);
    }
}
}
