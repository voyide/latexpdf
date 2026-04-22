import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
// THEME: BRUTALIST LIGHT PURPLE PAPER
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
    filled: true, fillColor: paperBg,
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
        <md.InlineSyntax>[
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
          BlockLatexSyntax(),
          InlineLatexSyntax(),
        ],
      ),
      builders: {
        'latex_block': LatexElementBuilder(mathStyle: MathStyle.display),
        'latex_inline': LatexElementBuilder(mathStyle: MathStyle.text),
      },
    );
  }
}

// ==========================================
// SHAPE & TIKZ ENGINE MODELS
// ==========================================
enum ToolType { line, arrow, rectangle, circle }

abstract class DiagramShape {
  final Offset start;
  final Offset end;
  DiagramShape(this.start, this.end);

  void drawUI(Canvas canvas, Paint paint);
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas);
  String toTikZ(double scale);
}

class LineShape extends DiagramShape {
  LineShape(super.start, super.end);

  @override
  void drawUI(Canvas canvas, Paint paint) => canvas.drawLine(start, end, paint);

  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    canvas.drawLine(start.dx, start.dy, end.dx, end.dy);
    canvas.strokePath();
  }

  @override
  String toTikZ(double scale) {
    return '\\draw [thick] (${(start.dx / scale).toStringAsFixed(2)}, ${-(start.dy / scale).toStringAsFixed(2)}) -- (${(end.dx / scale).toStringAsFixed(2)}, ${-(end.dy / scale).toStringAsFixed(2)});';
  }
}

class ArrowShape extends DiagramShape {
  ArrowShape(super.start, super.end);

  void _drawArrowHead(Canvas canvas, Paint paint) {
    double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    double arrowLen = 15.0;
    Offset p1 = Offset(end.dx - arrowLen * cos(angle - pi / 6), end.dy - arrowLen * sin(angle - pi / 6));
    Offset p2 = Offset(end.dx - arrowLen * cos(angle + pi / 6), end.dy - arrowLen * sin(angle + pi / 6));
    
    Path path = Path()..moveTo(end.dx, end.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close();
    canvas.drawPath(path, Paint()..color = paint.color..style = PaintingStyle.fill);
  }

  @override
  void drawUI(Canvas canvas, Paint paint) {
    canvas.drawLine(start, end, paint);
    _drawArrowHead(canvas, paint);
  }

  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    canvas.drawLine(start.dx, start.dy, end.dx, end.dy);
    canvas.strokePath();

    double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    double arrowLen = 15.0;
    double p1x = end.dx - arrowLen * cos(angle - pi / 6);
    double p1y = end.dy - arrowLen * sin(angle - pi / 6);
    double p2x = end.dx - arrowLen * cos(angle + pi / 6);
    double p2y = end.dy - arrowLen * sin(angle + pi / 6);

    canvas.moveTo(end.dx, end.dy);
    canvas.lineTo(p1x, p1y);
    canvas.lineTo(p2x, p2y);
    canvas.fillPath();
  }

  @override
  String toTikZ(double scale) {
    return '\\draw [thick, ->] (${(start.dx / scale).toStringAsFixed(2)}, ${-(start.dy / scale).toStringAsFixed(2)}) -- (${(end.dx / scale).toStringAsFixed(2)}, ${-(end.dy / scale).toStringAsFixed(2)});';
  }
}

class RectangleShape extends DiagramShape {
  RectangleShape(super.start, super.end);

  @override
  void drawUI(Canvas canvas, Paint paint) => canvas.drawRect(Rect.fromPoints(start, end), paint);

  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect.left, rect.top, rect.width, rect.height);
    canvas.strokePath();
  }

  @override
  String toTikZ(double scale) {
    return '\\draw [thick] (${(start.dx / scale).toStringAsFixed(2)}, ${-(start.dy / scale).toStringAsFixed(2)}) rectangle (${(end.dx / scale).toStringAsFixed(2)}, ${-(end.dy / scale).toStringAsFixed(2)});';
  }
}

class CircleShape extends DiagramShape {
  CircleShape(super.start, super.end);

  double get radius => (start - end).distance;

  @override
  void drawUI(Canvas canvas, Paint paint) => canvas.drawCircle(start, radius, paint);

  @override
  void drawPDF(pw.Context context, pw_pdf.PdfGraphics canvas) {
    canvas.drawEllipse(start.dx, start.dy, radius, radius);
    canvas.strokePath();
  }

  @override
  String toTikZ(double scale) {
    return '\\draw [thick] (${(start.dx / scale).toStringAsFixed(2)}, ${-(start.dy / scale).toStringAsFixed(2)}) circle (${(radius / scale).toStringAsFixed(2)});';
  }
}

// ==========================================
// DOCUMENT BLOCKS STATE
// ==========================================
abstract class DocBlock {
  final String id;
  DocBlock() : id = DateTime.now().microsecondsSinceEpoch.toString();
}

class TextBlockData extends DocBlock {
  String content = "";
  bool isEditing = true;
}

class VisualBlockData extends DocBlock {
  List<DiagramShape> shapes =[];
  double canvasHeight = 300.0;
}

class DocumentProvider extends ChangeNotifier {
  final List<DocBlock> _blocks =[];
  List<DocBlock> get blocks => _blocks;

  void addTextBlock() {
    _blocks.add(TextBlockData());
    notifyListeners();
  }

  void addVisualBlock() {
    _blocks.add(VisualBlockData());
    notifyListeners();
  }

  void updateText(String id, String newText) {
    final b = _blocks.firstWhere((b) => b.id == id) as TextBlockData;
    b.content = newText;
    notifyListeners();
  }

  void toggleTextEdit(String id) {
    final b = _blocks.firstWhere((b) => b.id == id) as TextBlockData;
    b.isEditing = !b.isEditing;
    notifyListeners();
  }

  void removeBlock(String id) {
    _blocks.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  void updateVisualShapes(String id, List<DiagramShape> newShapes) {
    final b = _blocks.firstWhere((b) => b.id == id) as VisualBlockData;
    b.shapes = List.from(newShapes);
    notifyListeners();
  }
}

// ==========================================
// UI: MAIN DOCUMENT EDITOR
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
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              if (docProvider.blocks.isEmpty) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportScreen()));
            },
          )
        ],
      ),
      body: docProvider.blocks.isEmpty
          ? const Center(
              child: Text(
                'SYSTEM EMPTY.\nINITIALIZE BLOCK TO BEGIN.',
                textAlign: TextAlign.center,
                style: TextStyle(color: inkBlack, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 16),
              itemCount: docProvider.blocks.length,
              itemBuilder: (context, index) {
                final block = docProvider.blocks[index];
                if (block is TextBlockData) {
                  return TextBlockWidget(block: block);
                } else if (block is VisualBlockData) {
                  return VisualBlockWidget(block: block);
                }
                return const SizedBox();
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children:[
          FloatingActionButton(
            heroTag: 'btn1',
            backgroundColor: inkBlack,
            foregroundColor: paperBg,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            onPressed: () => docProvider.addTextBlock(),
            child: const Icon(Icons.text_fields),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'btn2',
            backgroundColor: brassAccent,
            foregroundColor: inkBlack,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            onPressed: () => docProvider.addVisualBlock(),
            child: const Icon(Icons.draw),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// UI: TEXT BLOCK WIDGET
// ==========================================
class TextBlockWidget extends StatefulWidget {
  final TextBlockData block;
  const TextBlockWidget({super.key, required this.block});

  @override
  State<TextBlockWidget> createState() => _TextBlockWidgetState();
}

class _TextBlockWidgetState extends State<TextBlockWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.content);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:[
          Container(
            color: inkBlack,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                const Text('MARKDOWN/LATEX', style: TextStyle(color: paperBg, fontWeight: FontWeight.bold)),
                Row(
                  children:[
                    IconButton(
                      icon: Icon(widget.block.isEditing ? Icons.visibility : Icons.edit, color: paperBg, size: 20),
                      onPressed: () => context.read<DocumentProvider>().toggleTextEdit(widget.block.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.delete, color: rustRed, size: 20),
                      onPressed: () => context.read<DocumentProvider>().removeBlock(widget.block.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: widget.block.isEditing
                ? TextField(
                    controller: _controller,
                    maxLines: null,
                    minLines: 3,
                    style: const TextStyle(fontFamily: 'Courier', height: 1.5),
                    decoration: const InputDecoration(hintText: 'Type text or \$\$ \\int x dx \$\$'),
                    onChanged: (val) => context.read<DocumentProvider>().updateText(widget.block.id, val),
                  )
                : (widget.block.content.isEmpty
                    ? const Text("EMPTY_BLOCK", style: TextStyle(color: Colors.black38))
                    : BrutalistMarkdown(data: widget.block.content)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// UI: VISUAL BLOCK WIDGET (CANVAS)
// ==========================================
class VisualBlockWidget extends StatefulWidget {
  final VisualBlockData block;
  const VisualBlockWidget({super.key, required this.block});

  @override
  State<VisualBlockWidget> createState() => _VisualBlockWidgetState();
}

class _VisualBlockWidgetState extends State<VisualBlockWidget> {
  ToolType currentTool = ToolType.line;
  Offset? startPoint;
  Offset? currentPoint;
  late List<DiagramShape> localShapes;

  @override
  void initState() {
    super.initState();
    localShapes = List.from(widget.block.shapes);
  }

  void _saveShapes() {
    context.read<DocumentProvider>().updateVisualShapes(widget.block.id, localShapes);
  }

  DiagramShape _createShape(Offset start, Offset end) {
    switch (currentTool) {
      case ToolType.line: return LineShape(start, end);
      case ToolType.arrow: return ArrowShape(start, end);
      case ToolType.rectangle: return RectangleShape(start, end);
      case ToolType.circle: return CircleShape(start, end);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:[
          Container(
            color: brassAccent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                const Text('VISUAL_CANVAS (TIKZ)', style: TextStyle(color: inkBlack, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.delete, color: rustRed, size: 20),
                  onPressed: () => context.read<DocumentProvider>().removeBlock(widget.block.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              ],
            ),
          ),
          // Toolbar
          Container(
            padding: const EdgeInsets.all(8),
            color: inkBlack.withOpacity(0.05),
            child: Wrap(
              spacing: 8,
              children:[
                _ToolButton(
                  icon: Icons.horizontal_rule,
                  isActive: currentTool == ToolType.line,
                  onTap: () => setState(() => currentTool = ToolType.line),
                ),
                _ToolButton(
                  icon: Icons.arrow_right_alt,
                  isActive: currentTool == ToolType.arrow,
                  onTap: () => setState(() => currentTool = ToolType.arrow),
                ),
                _ToolButton(
                  icon: Icons.check_box_outline_blank,
                  isActive: currentTool == ToolType.rectangle,
                  onTap: () => setState(() => currentTool = ToolType.rectangle),
                ),
                _ToolButton(
                  icon: Icons.radio_button_unchecked,
                  isActive: currentTool == ToolType.circle,
                  onTap: () => setState(() => currentTool = ToolType.circle),
                ),
                Container(width: 2, height: 36, color: Colors.black26),
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: localShapes.isEmpty ? null : () {
                    setState(() => localShapes.removeLast());
                    _saveShapes();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: localShapes.isEmpty ? null : () {
                    setState(() => localShapes.clear());
                    _saveShapes();
                  },
                ),
              ],
            ),
          ),
          // Drawing Area
          GestureDetector(
            onPanStart: (details) => setState(() => startPoint = details.localPosition),
            onPanUpdate: (details) => setState(() => currentPoint = details.localPosition),
            onPanEnd: (details) {
              if (startPoint != null && currentPoint != null) {
                setState(() {
                  localShapes.add(_createShape(startPoint!, currentPoint!));
                  startPoint = null;
                  currentPoint = null;
                });
                _saveShapes();
              }
            },
            child: Container(
              height: widget.block.canvasHeight,
              width: double.infinity,
              color: Colors.white,
              child: CustomPaint(
                painter: BlockCanvasPainter(
                  shapes: localShapes,
                  activeShape: (startPoint != null && currentPoint != null) ? _createShape(startPoint!, currentPoint!) : null,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? inkBlack : Colors.transparent,
          border: Border.all(color: inkBlack, width: 2),
        ),
        child: Icon(icon, color: isActive ? paperBg : inkBlack, size: 20),
      ),
    );
  }
}

class BlockCanvasPainter extends CustomPainter {
  final List<DiagramShape> shapes;
  final DiagramShape? activeShape;

  BlockCanvasPainter({required this.shapes, this.activeShape});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()..color = Colors.black12..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 20) canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    for (double i = 0; i < size.height; i += 20) canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);

    final paint = Paint()
      ..color = inkBlack
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (var shape in shapes) shape.drawUI(canvas, paint);
    
    if (activeShape != null) {
      activeShape!.drawUI(canvas, paint..color = rustRed);
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
    const double scale = 50.0; // 50 pixels = 1 cm
    StringBuffer sb = StringBuffer();
    sb.writeln(r'\documentclass{article}');
    sb.writeln(r'\usepackage{tikz}');
    sb.writeln(r'\usepackage{amsmath}');
    sb.writeln(r'\begin{document}');
    sb.writeln();

    for (var block in blocks) {
      if (block is TextBlockData) {
        sb.writeln(block.content);
        sb.writeln();
      } else if (block is VisualBlockData) {
        sb.writeln(r'\begin{tikzpicture}');
        for (var shape in block.shapes) {
          sb.writeln('  ${shape.toTikZ(scale)}');
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
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 10),
              child: pw.Text(
                block.content,
                style: const pw.TextStyle(fontSize: 14),
              ),
            ));
          } else if (block is VisualBlockData) {
            widgets.add(
              pw.Container(
                height: block.canvasHeight,
                width: double.infinity,
                margin: const pw.EdgeInsets.symmetric(vertical: 10),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.CustomPaint(
                  size: pw_pdf.PdfPoint(400, block.canvasHeight),
                  painter: (pw_pdf.PdfGraphics canvas, pw_pdf.PdfPoint size) {
                    canvas.setColor(pw_pdf.PdfColors.black);
                    canvas.setLineWidth(2.0);
                    for (var shape in block.shapes) {
                      shape.drawPDF(context, canvas);
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
          bottom: const TabBar(
            indicator: BoxDecoration(color: inkBlack), labelColor: paperBg, unselectedLabelColor: inkBlack,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier'),
            tabs:[Tab(text: 'TRUE_TEX (OVERLEAF)'), Tab(text: 'QUICK_PDF (LOCAL)')],
          ),
        ),
        body: TabBarView(
          children:[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children:[
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('COPY CODE TO CLIPBOARD'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: latexCode));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('COPIED_TO_CLIPBOARD', style: TextStyle(fontFamily: 'Courier'))));
                    },
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(border: Border.all(color: inkBlack, width: 3), color: Colors.white),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        latexCode,
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
                      ),
                    ),
                  ),
                )
              ],
            ),
            PdfPreview(
              build: (format) => _generatePdf(blocks),
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: 'ProNotes_Output.pdf',
              previewPageMargin: const EdgeInsets.all(16),
            ),
          ],
        ),
      ),
    );
  }
}
