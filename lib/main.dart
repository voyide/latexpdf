import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Fixed: Required for Clipboard
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screenshot/screenshot.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers:[ChangeNotifierProvider(create: (_) => DocumentProvider())],
      child: const ProNotesApp(),
    ),
  );
}

// ==========================================
// THEME: BRUTALIST
// ==========================================
const Color paperBg = Color(0xFFE5DDF0);
const Color inkBlack = Color(0xFF1E1E1E);
const Color brassAccent = Color(0xFFB58840);
const Color rustRed = Color(0xFF9E3C27);
const Color steamGreen = Color(0xFF385E38);

final ThemeData brutalistTheme = ThemeData(
  fontFamily: 'Courier',
  scaffoldBackgroundColor: paperBg,
  colorScheme: const ColorScheme.light(
    primary: inkBlack, secondary: brassAccent, surface: paperBg,
    error: rustRed, onPrimary: paperBg, onSecondary: inkBlack, onSurface: inkBlack,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: paperBg, foregroundColor: inkBlack, elevation: 0, centerTitle: true,
    shape: Border(bottom: BorderSide(color: inkBlack, width: 3)),
  ),
  cardTheme: const CardThemeData(
    color: paperBg, elevation: 0, margin: EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: inkBlack, width: 2)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: inkBlack, foregroundColor: paperBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: const BorderSide(color: inkBlack, width: 2), padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: inkBlack,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: const BorderSide(color: inkBlack, width: 2), padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Colors.black, width: 2)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Colors.black, width: 2)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Colors.black, width: 3)),
  ),
  dividerTheme: const DividerThemeData(color: inkBlack, thickness: 2),
);

class ProNotesApp extends StatelessWidget {
  const ProNotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PRO NOTES LATEX',
      debugShowCheckedModeBanner: false,
      theme: brutalistTheme,
      home: const DocumentEditorScreen(),
    );
  }
}

// ==========================================
// AST MARKDOWN EXTENSIONS FOR LATEX
// ==========================================
class BlockLatexSyntax extends md.InlineSyntax {
  BlockLatexSyntax() : super(r'\$\$([^\$]+)\$\$');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('latex_block', match[1]!));
    return true;
  }
}
class InlineLatexSyntax extends md.InlineSyntax {
  InlineLatexSyntax() : super(r'\$([^\$]+)\$');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('latex_inline', match[1]!));
    return true;
  }
}
class LatexElementBuilder extends MarkdownElementBuilder {
  final MathStyle mathStyle;
  LatexElementBuilder({required this.mathStyle});
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Math.tex(
      element.textContent,
      mathStyle: mathStyle,
      textStyle: preferredStyle?.copyWith(fontSize: 16),
    );
  }
}
class BrutalistMarkdown extends StatelessWidget {
  final String data;
  const BrutalistMarkdown({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 16, height: 1.5, fontFamily: 'Courier', color: inkBlack),
        code: const TextStyle(backgroundColor: Colors.black12, fontFamily: 'Courier', color: inkBlack),
        codeblockDecoration: const BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.zero),
      ),
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        <md.InlineSyntax>[...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, BlockLatexSyntax(), InlineLatexSyntax()],
      ),
      builders: {'latex_block': LatexElementBuilder(mathStyle: MathStyle.display), 'latex_inline': LatexElementBuilder(mathStyle: MathStyle.text)},
    );
  }
}

// ==========================================
// ADVANCED VECTOR SHAPE SYSTEM
// ==========================================
enum ToolType { select, line, arrow, rectangle, circle }

abstract class DiagramShape {
  String id = DateTime.now().microsecondsSinceEpoch.toString();
  Offset start;
  Offset end;
  Color color;
  double strokeWidth;
  bool isFilled;

  DiagramShape({required this.start, required this.end, this.color = inkBlack, this.strokeWidth = 2.0, this.isFilled = false});

  void drawUI(Canvas canvas, Paint paint);
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas);
  String toTikZ(double scale);
  
  Map<String, dynamic> toJson();
  
  void move(Offset delta) {
    start += delta;
    end += delta;
  }
  
  bool contains(Offset point) {
    Rect bounds = Rect.fromPoints(start, end).inflate(strokeWidth + 5);
    return bounds.contains(point);
  }

  static DiagramShape fromJson(Map<String, dynamic> json) {
    Offset s = Offset(json['s_dx'], json['s_dy']);
    Offset e = Offset(json['e_dx'], json['e_dy']);
    Color c = Color(json['color']);
    double w = json['width'];
    bool f = json['filled'] ?? false;
    
    switch (json['type']) {
      case 'line': return LineShape(start: s, end: e, color: c, strokeWidth: w);
      case 'arrow': return ArrowShape(start: s, end: e, color: c, strokeWidth: w);
      case 'rect': return RectangleShape(start: s, end: e, color: c, strokeWidth: w, isFilled: f);
      case 'circle': return CircleShape(start: s, end: e, color: c, strokeWidth: w, isFilled: f);
      default: return LineShape(start: s, end: e, color: c, strokeWidth: w);
    }
  }

  Map<String, dynamic> _baseJson(String type) => {
    'type': type, 's_dx': start.dx, 's_dy': start.dy, 'e_dx': end.dx, 'e_dy': end.dy,
    'color': color.toARGB32(), 'width': strokeWidth, 'filled': isFilled
  };
}

class LineShape extends DiagramShape {
  LineShape({required super.start, required super.end, super.color, super.strokeWidth, super.isFilled});
  @override
  void drawUI(Canvas canvas, Paint paint) => canvas.drawLine(start, end, paint);
  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) { canvas.drawLine(start.dx, start.dy, end.dx, end.dy); canvas.strokePath(); }
  @override
  String toTikZ(double scale) => '\\draw [color_${color.toARGB32()}, line width=${strokeWidth}pt] (${(start.dx/scale).toStringAsFixed(2)}, ${(-(start.dy/scale)).toStringAsFixed(2)}) -- (${(end.dx/scale).toStringAsFixed(2)}, ${(-(end.dy/scale)).toStringAsFixed(2)});';
  @override
  Map<String, dynamic> toJson() => _baseJson('line');
}

class ArrowShape extends DiagramShape {
  ArrowShape({required super.start, required super.end, super.color, super.strokeWidth, super.isFilled});
  void _drawArrowHead(Canvas canvas, Paint paint) {
    double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    double arrowLen = 15.0;
    Offset p1 = Offset(end.dx - arrowLen * cos(angle - pi / 6), end.dy - arrowLen * sin(angle - pi / 6));
    Offset p2 = Offset(end.dx - arrowLen * cos(angle + pi / 6), end.dy - arrowLen * sin(angle + pi / 6));
    Path path = Path()..moveTo(end.dx, end.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close();
    canvas.drawPath(path, Paint()..color = paint.color..style = PaintingStyle.fill);
  }
  @override
  void drawUI(Canvas canvas, Paint paint) { canvas.drawLine(start, end, paint); _drawArrowHead(canvas, paint); }
  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    canvas.drawLine(start.dx, start.dy, end.dx, end.dy); canvas.strokePath();
    double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    double arrowLen = 15.0;
    canvas.moveTo(end.dx, end.dy);
    canvas.lineTo(end.dx - arrowLen * cos(angle - pi / 6), end.dy - arrowLen * sin(angle - pi / 6));
    canvas.lineTo(end.dx - arrowLen * cos(angle + pi / 6), end.dy - arrowLen * sin(angle + pi / 6));
    canvas.fillPath();
  }
  @override
  String toTikZ(double scale) => '\\draw[color_${color.toARGB32()}, ->, line width=${strokeWidth}pt] (${(start.dx/scale).toStringAsFixed(2)}, ${(-(start.dy/scale)).toStringAsFixed(2)}) -- (${(end.dx/scale).toStringAsFixed(2)}, ${(-(end.dy/scale)).toStringAsFixed(2)});';
  @override
  Map<String, dynamic> toJson() => _baseJson('arrow');
}

class RectangleShape extends DiagramShape {
  RectangleShape({required super.start, required super.end, super.color, super.strokeWidth, super.isFilled});
  @override
  void drawUI(Canvas canvas, Paint paint) => canvas.drawRect(Rect.fromPoints(start, end), paint);
  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    final r = Rect.fromPoints(start, end);
    canvas.drawRect(r.left, r.top, r.width, r.height);
    isFilled ? canvas.fillPath() : canvas.strokePath();
  }
  @override
  String toTikZ(double scale) {
    String cmd = isFilled ? '\\fill' : '\\draw';
    return '$cmd[color_${color.toARGB32()}, line width=${strokeWidth}pt] (${(start.dx/scale).toStringAsFixed(2)}, ${(-(start.dy/scale)).toStringAsFixed(2)}) rectangle (${(end.dx/scale).toStringAsFixed(2)}, ${(-(end.dy/scale)).toStringAsFixed(2)});';
  }
  @override
  Map<String, dynamic> toJson() => _baseJson('rect');
}

class CircleShape extends DiagramShape {
  CircleShape({required super.start, required super.end, super.color, super.strokeWidth, super.isFilled});
  double get radius => (start - end).distance;
  @override
  void drawUI(Canvas canvas, Paint paint) => canvas.drawCircle(start, radius, paint);
  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    canvas.drawEllipse(start.dx, start.dy, radius, radius);
    isFilled ? canvas.fillPath() : canvas.strokePath();
  }
  @override
  String toTikZ(double scale) {
    String cmd = isFilled ? '\\fill' : '\\draw';
    return '$cmd[color_${color.toARGB32()}, line width=${strokeWidth}pt] (${(start.dx/scale).toStringAsFixed(2)}, ${(-(start.dy/scale)).toStringAsFixed(2)}) circle (${(radius/scale).toStringAsFixed(2)});';
  }
  @override
  Map<String, dynamic> toJson() => _baseJson('circle');
}

// ==========================================
// DOCUMENT MODELS & PROVIDER
// ==========================================
abstract class DocBlock {
  final String id = DateTime.now().microsecondsSinceEpoch.toString();
}

class TextBlockData extends DocBlock {
  String content = "";
  bool isEditing = true;
  ScreenshotController screenshotController = ScreenshotController();
  Uint8List? lastCapturedImage;
}

class LayerData {
  String id = DateTime.now().microsecondsSinceEpoch.toString();
  String name;
  bool isVisible = true;
  double opacity = 1.0;
  List<DiagramShape> shapes =[];
  LayerData({required this.name});
}

class VisualBlockData extends DocBlock {
  List<LayerData> layers = [LayerData(name: "Base Layer")];
  double canvasHeight = 400.0;
  double canvasWidth = 400.0;
  
  List<DiagramShape> get flatShapes {
    List<DiagramShape> all =[];
    for (var l in layers) { if (l.isVisible) all.addAll(l.shapes); }
    return all;
  }
}

class DocumentProvider extends ChangeNotifier {
  final List<DocBlock> _blocks =[];
  List<DocBlock> get blocks => _blocks;

  void addTextBlock() { _blocks.add(TextBlockData()); notifyListeners(); }
  void addVisualBlock() { _blocks.add(VisualBlockData()); notifyListeners(); }
  void updateText(String id, String text) { (_blocks.firstWhere((b) => b.id == id) as TextBlockData).content = text; notifyListeners(); }
  void toggleTextEdit(String id) {
    var b = _blocks.firstWhere((b) => b.id == id) as TextBlockData;
    b.isEditing = !b.isEditing;
    notifyListeners();
  }
  void removeBlock(String id) { _blocks.removeWhere((b) => b.id == id); notifyListeners(); }
  void updateVisualBlock(String id) { notifyListeners(); } 
}

// ==========================================
// ARTIFACT SYSTEM (SharedPreferences)
// ==========================================
class DrawingArtifact {
  String name;
  List<DiagramShape> shapes;
  DrawingArtifact({required this.name, required this.shapes});
  Map<String, dynamic> toJson() => { 'name': name, 'shapes': shapes.map((s) => s.toJson()).toList() };
  static DrawingArtifact fromJson(Map<String, dynamic> json) => DrawingArtifact(
    name: json['name'],
    shapes: (json['shapes'] as List).map((s) => DiagramShape.fromJson(s)).toList()
  );
}

class ArtifactManager {
  static Future<void> saveArtifact(DrawingArtifact artifact) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> existing = prefs.getStringList('artifacts') ??[];
    existing.add(jsonEncode(artifact.toJson()));
    await prefs.setStringList('artifacts', existing);
  }
  static Future<List<DrawingArtifact>> getArtifacts() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> existing = prefs.getStringList('artifacts') ??[];
    return existing.map((s) => DrawingArtifact.fromJson(jsonDecode(s))).toList();
  }
}

// ==========================================
// UI: MAIN EDITOR
// ==========================================
class DocumentEditorScreen extends StatelessWidget {
  const DocumentEditorScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('DOCUMENT_EDITOR', style: TextStyle(fontWeight: FontWeight.bold)),
        actions:[
          IconButton(icon: const Icon(Icons.print), onPressed: () async {
            if (docProvider.blocks.isEmpty) return;
            // Pre-capture all text blocks for PDF rendering
            for (var b in docProvider.blocks) {
              if (b is TextBlockData && !b.isEditing) {
                b.lastCapturedImage = await b.screenshotController.capture();
              }
            }
            if(context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportScreen()));
          })
        ],
      ),
      body: docProvider.blocks.isEmpty
          ? const Center(child: Text('SYSTEM EMPTY.\nINITIALIZE BLOCK TO BEGIN.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 16),
              itemCount: docProvider.blocks.length,
              itemBuilder: (context, index) {
                final block = docProvider.blocks[index];
                if (block is TextBlockData) return TextBlockWidget(block: block);
                if (block is VisualBlockData) return VisualBlockPreview(block: block);
                return const SizedBox();
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children:[
          FloatingActionButton(heroTag: 'btn1', backgroundColor: inkBlack, foregroundColor: paperBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), onPressed: () => docProvider.addTextBlock(), child: const Icon(Icons.text_fields)),
          const SizedBox(height: 16),
          FloatingActionButton(heroTag: 'btn2', backgroundColor: brassAccent, foregroundColor: inkBlack, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), onPressed: () => docProvider.addVisualBlock(), child: const Icon(Icons.draw)),
        ],
      ),
    );
  }
}

class TextBlockWidget extends StatelessWidget {
  final TextBlockData block;
  const TextBlockWidget({super.key, required this.block});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:[
          Container(
            color: inkBlack, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                const Text('MARKDOWN/LATEX', style: TextStyle(color: paperBg, fontWeight: FontWeight.bold)),
                Row(
                  children:[
                    IconButton(icon: Icon(block.isEditing ? Icons.visibility : Icons.edit, color: paperBg, size: 20), onPressed: () => context.read<DocumentProvider>().toggleTextEdit(block.id), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    const SizedBox(width: 16),
                    IconButton(icon: const Icon(Icons.delete, color: rustRed, size: 20), onPressed: () => context.read<DocumentProvider>().removeBlock(block.id), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ],
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: block.isEditing
                ? TextFormField(
                    initialValue: block.content, maxLines: null, minLines: 3, style: const TextStyle(fontFamily: 'Courier', height: 1.5),
                    decoration: const InputDecoration(hintText: 'Type text or \$\$ \\frac{a}{b} \$\$'),
                    onChanged: (val) => context.read<DocumentProvider>().updateText(block.id, val),
                  )
                : Screenshot(
                    controller: block.screenshotController,
                    child: Container(
                      color: paperBg, // Ensures background is solid for PDF screenshot
                      child: block.content.isEmpty ? const Text("EMPTY_BLOCK", style: TextStyle(color: Colors.black38)) : BrutalistMarkdown(data: block.content),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class VisualBlockPreview extends StatelessWidget {
  final VisualBlockData block;
  const VisualBlockPreview({super.key, required this.block});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:[
          Container(
            color: brassAccent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                const Text('VISUAL_CANVAS', style: TextStyle(color: inkBlack, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.delete, color: rustRed, size: 20), onPressed: () => context.read<DocumentProvider>().removeBlock(block.id), padding: EdgeInsets.zero, constraints: const BoxConstraints())
              ],
            ),
          ),
          Container(
            height: 200, color: Colors.white,
            child: Stack(
              children:[
                CustomPaint(size: const Size(double.infinity, 200), painter: _PreviewPainter(block)),
                Center(child: FilledButton.icon(icon: const Icon(Icons.edit), label: const Text('OPEN EDITOR'), onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AdvancedDrawingEditor(block: block)));
                }))
              ],
            ),
          )
        ],
      ),
    );
  }
}
class _PreviewPainter extends CustomPainter {
  final VisualBlockData block;
  _PreviewPainter(this.block);
  @override
  void paint(Canvas canvas, Size size) {
    for (var layer in block.layers) {
      if (!layer.isVisible) continue;
      canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black.withValues(alpha: layer.opacity));
      for (var shape in layer.shapes) {
        Paint p = Paint()..color = shape.color..strokeWidth = shape.strokeWidth..style = shape.isFilled ? PaintingStyle.fill : PaintingStyle.stroke;
        shape.drawUI(canvas, p);
      }
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// ADVANCED DRAWING EDITOR (Fullscreen)
// ==========================================
class AdvancedDrawingEditor extends StatefulWidget {
  final VisualBlockData block;
  const AdvancedDrawingEditor({super.key, required this.block});
  @override
  State<AdvancedDrawingEditor> createState() => _AdvancedDrawingEditorState();
}

class _AdvancedDrawingEditorState extends State<AdvancedDrawingEditor> {
  int currentLayerIndex = 0;
  ToolType currentTool = ToolType.line;
  Color currentColor = inkBlack;
  double currentStrokeWidth = 2.0;
  bool isFilled = false;
  
  bool mirrorX = false;
  bool mirrorY = false;
  
  TextEditingController rotLockCtrl = TextEditingController();
  TextEditingController ratioLockCtrl = TextEditingController();
  
  Offset? startPoint;
  Offset? currentPoint;
  DiagramShape? selectedShape;
  Offset? lastDragPos;

  void _save() => context.read<DocumentProvider>().updateVisualBlock(widget.block.id);

  LayerData get activeLayer => widget.block.layers[currentLayerIndex];

  DiagramShape? _createShape(Offset s, Offset e) {
    // Apply Rotation Lock
    if (rotLockCtrl.text.isNotEmpty && currentTool == ToolType.line) {
      double? angleDeg = double.tryParse(rotLockCtrl.text);
      if (angleDeg != null) {
        double angleRad = angleDeg * pi / 180;
        double dist = (e - s).distance;
        e = Offset(s.dx + dist * cos(angleRad), s.dy - dist * sin(angleRad)); // -sin because Y is down
      }
    }
    // Apply Ratio Lock
    if (ratioLockCtrl.text.isNotEmpty && currentTool == ToolType.rectangle) {
      List<String> parts = ratioLockCtrl.text.split(':');
      if (parts.length == 2) {
        double? wRatio = double.tryParse(parts[0]);
        double? hRatio = double.tryParse(parts[1]);
        if (wRatio != null && hRatio != null) {
          double width = e.dx - s.dx;
          double height = width * (hRatio / wRatio);
          e = Offset(e.dx, s.dy + height);
        }
      }
    }

    switch (currentTool) {
      case ToolType.line: return LineShape(start: s, end: e, color: currentColor, strokeWidth: currentStrokeWidth);
      case ToolType.arrow: return ArrowShape(start: s, end: e, color: currentColor, strokeWidth: currentStrokeWidth);
      case ToolType.rectangle: return RectangleShape(start: s, end: e, color: currentColor, strokeWidth: currentStrokeWidth, isFilled: isFilled);
      case ToolType.circle: return CircleShape(start: s, end: e, color: currentColor, strokeWidth: currentStrokeWidth, isFilled: isFilled);
      default: return null;
    }
  }

  void _handlePanStart(DragStartDetails details) {
    if (currentTool == ToolType.select) {
      selectedShape = null;
      for (var s in activeLayer.shapes.reversed) {
        if (s.contains(details.localPosition)) { selectedShape = s; lastDragPos = details.localPosition; break; }
      }
      setState(() {});
    } else {
      setState(() => startPoint = details.localPosition);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (currentTool == ToolType.select && selectedShape != null && lastDragPos != null) {
      Offset delta = details.localPosition - lastDragPos!;
      setState(() { selectedShape!.move(delta); lastDragPos = details.localPosition; });
    } else if (startPoint != null) {
      setState(() => currentPoint = details.localPosition);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (currentTool != ToolType.select && startPoint != null && currentPoint != null) {
      DiagramShape? primary = _createShape(startPoint!, currentPoint!);
      if (primary != null) {
        setState(() {
          activeLayer.shapes.add(primary);
          // Symmetry logic
          double cx = widget.block.canvasWidth / 2;
          double cy = widget.block.canvasHeight / 2;
          if (mirrorX) {
            Offset ms = Offset(cx + (cx - primary.start.dx), primary.start.dy);
            Offset me = Offset(cx + (cx - primary.end.dx), primary.end.dy);
            DiagramShape? msShape = _createShape(ms, me);
            if(msShape != null) activeLayer.shapes.add(msShape);
          }
          if (mirrorY) {
            Offset ms = Offset(primary.start.dx, cy + (cy - primary.start.dy));
            Offset me = Offset(primary.end.dx, cy + (cy - primary.end.dy));
            DiagramShape? msShape = _createShape(ms, me);
            if(msShape != null) activeLayer.shapes.add(msShape);
          }
          startPoint = null; currentPoint = null;
        });
        _save();
      }
    }
    lastDragPos = null;
  }

  void _openColorPicker() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('SELECT_COLOR'),
      content: SingleChildScrollView(child: ColorPicker(pickerColor: currentColor, onColorChanged: (c) => setState(() => currentColor = c))),
      actions:[FilledButton(child: const Text('DONE'), onPressed: () => Navigator.pop(ctx))],
    ));
  }

  void _openArtifactsMenu() async {
    List<DrawingArtifact> artifacts = await ArtifactManager.getArtifacts();
    if (!mounted) return;
    showModalBottomSheet(context: context, builder: (ctx) => Container(
      padding: const EdgeInsets.all(16), color: paperBg,
      child: Column(
        children:[
          const Text('ARTIFACT_LIBRARY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const Divider(),
          Expanded(child: ListView.builder(
            itemCount: artifacts.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(artifacts[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: FilledButton(child: const Text('LOAD'), onPressed: () {
                setState(() {
                  LayerData newLayer = LayerData(name: "Artifact: ${artifacts[i].name}");
                  newLayer.shapes = artifacts[i].shapes; // Deep copy needed in prod, but keeping simple
                  widget.block.layers.add(newLayer);
                  currentLayerIndex = widget.block.layers.length - 1;
                });
                _save(); Navigator.pop(ctx);
              }),
            ),
          )),
          FilledButton.icon(icon: const Icon(Icons.save), label: const Text('SAVE CURRENT LAYER AS ARTIFACT'), onPressed: () {
            ArtifactManager.saveArtifact(DrawingArtifact(name: "ART_${DateTime.now().millisecondsSinceEpoch}", shapes: List.from(activeLayer.shapes)));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SAVED')));
          })
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ADVANCED_EDITOR'), actions:[
        IconButton(icon: const Icon(Icons.grid_on), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PointGridEditor(block: widget.block)))),
        IconButton(icon: const Icon(Icons.library_books), onPressed: _openArtifactsMenu),
      ]),
      body: Row(
        children:[
          // Left Sidebar Tools
          Container(
            width: 70, color: inkBlack.withValues(alpha: 0.05),
            child: Column(
              children:[
                IconButton(icon: const Icon(Icons.ads_click), color: currentTool==ToolType.select ? rustRed : inkBlack, onPressed: ()=>setState(()=>currentTool=ToolType.select)),
                IconButton(icon: const Icon(Icons.horizontal_rule), color: currentTool==ToolType.line ? rustRed : inkBlack, onPressed: ()=>setState(()=>currentTool=ToolType.line)),
                IconButton(icon: const Icon(Icons.arrow_right_alt), color: currentTool==ToolType.arrow ? rustRed : inkBlack, onPressed: ()=>setState(()=>currentTool=ToolType.arrow)),
                IconButton(icon: const Icon(Icons.check_box_outline_blank), color: currentTool==ToolType.rectangle ? rustRed : inkBlack, onPressed: ()=>setState(()=>currentTool=ToolType.rectangle)),
                IconButton(icon: const Icon(Icons.radio_button_unchecked), color: currentTool==ToolType.circle ? rustRed : inkBlack, onPressed: ()=>setState(()=>currentTool=ToolType.circle)),
                const Divider(),
                IconButton(icon: const Icon(Icons.format_color_fill), color: isFilled ? rustRed : inkBlack, onPressed: ()=>setState(()=>isFilled = !isFilled)),
                GestureDetector(onTap: _openColorPicker, child: Container(margin: const EdgeInsets.all(8), width: 30, height: 30, decoration: BoxDecoration(color: currentColor, border: Border.all(color: inkBlack, width: 2)))),
                const Divider(),
                IconButton(icon: const Icon(Icons.flip), color: mirrorX ? rustRed : inkBlack, tooltip: "Mirror X", onPressed: ()=>setState(()=>mirrorX = !mirrorX)),
                IconButton(icon: const Icon(Icons.flip_camera_android), color: mirrorY ? rustRed : inkBlack, tooltip: "Mirror Y", onPressed: ()=>setState(()=>mirrorY = !mirrorY)),
              ],
            ),
          ),
          // Main Canvas
          Expanded(
            child: Column(
              children:[
                Container(
                  color: Colors.white, height: 60,
                  child: Row(
                    children:[
                      const SizedBox(width: 8), const Text("ROT_LOCK°:"), SizedBox(width: 60, child: TextField(controller: rotLockCtrl, decoration: const InputDecoration(isDense: true))),
                      const SizedBox(width: 16), const Text("RATIO(W:H):"), SizedBox(width: 60, child: TextField(controller: ratioLockCtrl, decoration: const InputDecoration(isDense: true))),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(100), minScale: 0.1, maxScale: 5.0,
                    child: Center(
                      child: GestureDetector(
                        onPanStart: _handlePanStart, onPanUpdate: _handlePanUpdate, onPanEnd: _handlePanEnd,
                        child: Container(
                          width: widget.block.canvasWidth, height: widget.block.canvasHeight,
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: inkBlack, width: 2), boxShadow: const[BoxShadow(color: Colors.black26, blurRadius: 10)]),
                          child: CustomPaint(
                            painter: AdvancedCanvasPainter(block: widget.block, activeShape: (startPoint!=null && currentPoint!=null)?_createShape(startPoint!, currentPoint!):null, selectedShape: selectedShape),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Right Sidebar Layers
          Container(
            width: 150, color: brassAccent.withValues(alpha: 0.2),
            child: Column(
              children:[
                const Padding(padding: EdgeInsets.all(8.0), child: Text("LAYERS", style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.block.layers.length,
                    itemBuilder: (ctx, i) {
                      LayerData l = widget.block.layers[i];
                      return Container(
                        color: currentLayerIndex == i ? Colors.white54 : Colors.transparent,
                        child: ListTile(
                          title: Text(l.name, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(icon: Icon(l.isVisible ? Icons.visibility : Icons.visibility_off, size: 16), onPressed: ()=>setState((){ l.isVisible = !l.isVisible; _save();})),
                          onTap: ()=>setState(()=>currentLayerIndex = i),
                          onLongPress: () { setState((){ widget.block.layers.removeAt(i); currentLayerIndex=max(0, currentLayerIndex-1); _save();}); },
                        ),
                      );
                    },
                  ),
                ),
                FilledButton(onPressed: ()=>setState((){ widget.block.layers.add(LayerData(name: "Layer ${widget.block.layers.length+1}")); _save();}), child: const Text("ADD LAYER"))
              ],
            ),
          )
        ],
      ),
    );
  }
}

class AdvancedCanvasPainter extends CustomPainter {
  final VisualBlockData block;
  final DiagramShape? activeShape;
  final DiagramShape? selectedShape;
  AdvancedCanvasPainter({required this.block, this.activeShape, this.selectedShape});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final Paint gridPaint = Paint()..color = Colors.black12..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 20) canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    for (double i = 0; i < size.height; i += 20) canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);

    for (var layer in block.layers) {
      if (!layer.isVisible) continue;
      canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black.withValues(alpha: layer.opacity));
      for (var shape in layer.shapes) {
        Paint p = Paint()..color = shape.color..strokeWidth = shape.strokeWidth..style = shape.isFilled ? PaintingStyle.fill : PaintingStyle.stroke;
        shape.drawUI(canvas, p);
        if (shape == selectedShape) {
          canvas.drawRect(Rect.fromPoints(shape.start, shape.end).inflate(shape.strokeWidth+2), Paint()..color=rustRed..style=PaintingStyle.stroke..strokeWidth=2);
        }
      }
      canvas.restore();
    }
    if (activeShape != null) {
      Paint p = Paint()..color = activeShape!.color..strokeWidth = activeShape!.strokeWidth..style = activeShape!.isFilled ? PaintingStyle.fill : PaintingStyle.stroke;
      activeShape!.drawUI(canvas, p);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// POINT GRID EDITOR (Special Diagram Tool)
// ==========================================
class PointGridEditor extends StatefulWidget {
  final VisualBlockData block;
  const PointGridEditor({super.key, required this.block});
  @override
  State<PointGridEditor> createState() => _PointGridEditorState();
}

class GridLine {
  int p1, p2;
  Color color;
  GridLine(this.p1, this.p2, this.color);
}

class _PointGridEditorState extends State<PointGridEditor> {
  int rows = 10;
  int cols = 10;
  double spacingX = 30.0;
  double spacingY = 30.0;
  
  List<Offset> points = [];
  List<GridLine> lines =[];
  List<GridLine> redoStack =[];
  
  int? selectedPointIndex;
  Color currentLineColor = inkBlack;
  double globalStrokeWidth = 3.0;

  @override
  void initState() { super.initState(); _generatePoints(); }

  void _generatePoints() {
    points.clear(); lines.clear(); redoStack.clear(); selectedPointIndex = null;
    double startX = (widget.block.canvasWidth - (cols - 1) * spacingX) / 2;
    double startY = (widget.block.canvasHeight - (rows - 1) * spacingY) / 2;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        points.add(Offset(startX + c * spacingX, startY + r * spacingY));
      }
    }
  }

  void _handleTap(TapUpDetails details) {
    int? tappedIdx;
    for (int i = 0; i < points.length; i++) {
      if ((points[i] - details.localPosition).distance < 15.0) { tappedIdx = i; break; }
    }
    if (tappedIdx == null) return;

    final int safeTappedIdx = tappedIdx;

    setState(() {
      if (selectedPointIndex == null) {
        selectedPointIndex = safeTappedIdx;
      } else if (selectedPointIndex == safeTappedIdx) {
        lines.removeWhere((l) => l.p1 == safeTappedIdx || l.p2 == safeTappedIdx);
        selectedPointIndex = null;
      } else {
        lines.add(GridLine(selectedPointIndex!, safeTappedIdx, currentLineColor));
        redoStack.clear();
        selectedPointIndex = safeTappedIdx;
      }
    });
  }

  void _saveToCanvas() {
    LayerData newLayer = LayerData(name: "Point Grid ${DateTime.now().minute}");
    for (var l in lines) {
      newLayer.shapes.add(LineShape(start: points[l.p1], end: points[l.p2], color: l.color, strokeWidth: globalStrokeWidth));
    }
    widget.block.layers.add(newLayer);
    context.read<DocumentProvider>().updateVisualBlock(widget.block.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POINT_GRID_TOOL'), actions:[FilledButton(onPressed: _saveToCanvas, child: const Text('SAVE_SHAPE'))]),
      body: Column(
        children:[
          Container(
            padding: const EdgeInsets.all(8), color: brassAccent.withValues(alpha: 0.2),
            child: Row(
              children:[
                IconButton(icon: const Icon(Icons.undo), onPressed: lines.isEmpty ? null : () { setState(() { redoStack.add(lines.removeLast()); }); }),
                IconButton(icon: const Icon(Icons.redo), onPressed: redoStack.isEmpty ? null : () { setState(() { lines.add(redoStack.removeLast()); }); }),
                const Spacer(),
                GestureDetector(onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(content: SingleChildScrollView(child: ColorPicker(pickerColor: currentLineColor, onColorChanged: (c) => setState(() => currentLineColor = c))))), child: Container(width: 30, height: 30, color: currentLineColor)),
                const SizedBox(width: 16),
                const Text("SIZE:"), Slider(value: globalStrokeWidth, min: 1, max: 10, onChanged: (v)=>setState(()=>globalStrokeWidth=v)),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTapUp: _handleTap,
              child: Container(
                width: widget.block.canvasWidth, height: widget.block.canvasHeight, color: Colors.white,
                child: CustomPaint(painter: PointGridPainter(points, lines, selectedPointIndex, globalStrokeWidth)),
              ),
            ),
          )
        ],
      ),
    );
  }
}
class PointGridPainter extends CustomPainter {
  final List<Offset> points;
  final List<GridLine> lines;
  final int? selectedIdx;
  final double strokeW;
  PointGridPainter(this.points, this.lines, this.selectedIdx, this.strokeW);
  @override
  void paint(Canvas canvas, Size size) {
    for (var l in lines) canvas.drawLine(points[l.p1], points[l.p2], Paint()..color=l.color..strokeWidth=strokeW);
    for (int i=0; i<points.length; i++) {
      canvas.drawCircle(points[i], 4, Paint()..color = (i == selectedIdx) ? rustRed : Colors.black26);
      if(i == selectedIdx) canvas.drawCircle(points[i], 8, Paint()..color=rustRed..style=PaintingStyle.stroke..strokeWidth=2);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// EXPORT ENGINE (Dual-Mode)
// ==========================================
class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  String _generateLatexSource(List<DocBlock> blocks) {
    const double scale = 50.0;
    StringBuffer sb = StringBuffer();
    sb.writeln(r'\documentclass{article}');
    sb.writeln(r'\usepackage{tikz}');
    sb.writeln(r'\usepackage{amsmath}');
    
    // Extract unique colors to define at top
    Set<Color> colors = {};
    for(var b in blocks) {
      if (b is VisualBlockData) {
        for(var l in b.layers) {
          for(var s in l.shapes) colors.add(s.color);
        }
      }
    }
    for(Color c in colors) {
      int cv = c.toARGB32();
      sb.writeln('\\definecolor{color_$cv}{RGB}{${(c.r * 255).round().clamp(0, 255)},${(c.g * 255).round().clamp(0, 255)},${(c.b * 255).round().clamp(0, 255)}}');
    }
    sb.writeln(r'\begin{document}');
    sb.writeln();

    for (var block in blocks) {
      if (block is TextBlockData) {
        sb.writeln(block.content); sb.writeln();
      } else if (block is VisualBlockData) {
        sb.writeln(r'\begin{tikzpicture}');
        for (var layer in block.layers) {
          if (!layer.isVisible) continue;
          sb.writeln('  \\begin{scope}[opacity=${layer.opacity}]');
          for (var shape in layer.shapes) sb.writeln('    ${shape.toTikZ(scale)}');
          sb.writeln('  \\end{scope}');
        }
        sb.writeln(r'\end{tikzpicture}');
        sb.writeln();
      }
    }
    sb.writeln(r'\end{document}');
    return sb.toString();
  }

  Future<Uint8List> _generatePdf(List<DocBlock> blocks) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: pw_pdf.PdfPageFormat.a4,
      build: (pw.Context context) {
        List<pw.Widget> widgets =[];
        for (var block in blocks) {
          if (block is TextBlockData) {
            if (block.lastCapturedImage != null) {
              // EXACT WYSIWYG for math in offline PDF!
              widgets.add(pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 10), child: pw.Image(pw.MemoryImage(block.lastCapturedImage!))));
            } else {
              widgets.add(pw.Text(block.content));
            }
          } else if (block is VisualBlockData) {
            widgets.add(
              pw.Container(
                height: block.canvasHeight, width: double.infinity, margin: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.CustomPaint(
                  size: pw_pdf.PdfPoint(400, block.canvasHeight),
                  painter: (pw_pdf.PdfGraphics canvas, pw_pdf.PdfPoint size) {
                    for (var layer in block.layers) {
                      if(!layer.isVisible) continue;
                      for (var shape in layer.shapes) {
                        canvas.setColor(pw_pdf.PdfColor.fromInt(shape.color.toARGB32()));
                        canvas.setLineWidth(shape.strokeWidth);
                        shape.drawPDF(context, canvas);
                      }
                    }
                  },
                ),
              ),
            );
          }
        }
        return widgets;
      },
    ));
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    final blocks = context.read<DocumentProvider>().blocks;
    final latexCode = _generateLatexSource(blocks);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OUTPUT_COMPILER'),
          bottom: const TabBar(indicator: BoxDecoration(color: inkBlack), labelColor: paperBg, unselectedLabelColor: inkBlack, labelStyle: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier'), tabs:[Tab(text: 'TRUE_TEX (OVERLEAF)'), Tab(text: 'QUICK_PDF (LOCAL)')]),
        ),
        body: TabBarView(
          children:[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children:[
                Padding(padding: const EdgeInsets.all(16.0), child: FilledButton.icon(icon: const Icon(Icons.copy), label: const Text('COPY CODE TO CLIPBOARD'), onPressed: () { Clipboard.setData(ClipboardData(text: latexCode)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('COPIED_TO_CLIPBOARD'))); })),
                Expanded(child: Container(margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: inkBlack, width: 3), color: Colors.white), child: SingleChildScrollView(child: SelectableText(latexCode, style: const TextStyle(fontFamily: 'Courier', fontSize: 12))))),
              ],
            ),
            PdfPreview(build: (format) => _generatePdf(blocks), canChangeOrientation: false, canChangePageFormat: false, pdfFileName: 'ProNotes_Output.pdf', previewPageMargin: const EdgeInsets.all(16)),
          ],
        ),
      ),
    );
  }
}
