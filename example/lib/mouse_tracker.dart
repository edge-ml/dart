import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class CursorTracker extends StatefulWidget {
  final void Function(double a, double b) onCursorUpdate;

  const CursorTracker({super.key, required this.onCursorUpdate});

  @override
  State<CursorTracker> createState() => _CursorTrackerState();
}

class _CursorTrackerState extends State<CursorTracker> {
  Offset _cursorPosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        setState(() {
          _cursorPosition = event.localPosition;
        });
        widget.onCursorUpdate(_cursorPosition.dx, _cursorPosition.dy);
      },
      child: GestureDetector(
        onTapDown: (TapDownDetails details) {
          setState(() {
            _cursorPosition = details.localPosition;
          });
          widget.onCursorUpdate(_cursorPosition.dx, _cursorPosition.dy);
        },
        onPanStart: (DragStartDetails details) {
          setState(() {
            _cursorPosition = details.localPosition;
          });
          widget.onCursorUpdate(_cursorPosition.dx, _cursorPosition.dy);
        },
        onPanUpdate: (DragUpdateDetails details) {
          setState(() {
            _cursorPosition = details.localPosition;
          });
          widget.onCursorUpdate(_cursorPosition.dx, _cursorPosition.dy);
        },
        child: Container(
          color: Colors.grey[200],
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Position: (${_cursorPosition.dx.toStringAsFixed(2)}, ${_cursorPosition.dy.toStringAsFixed(2)})',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
