import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'tap_target.dart';

/// Presents a sheet (HIG, Sheets): anchored to the bottom, 22 pt top radii,
/// a 36 × 5 grabber, the elevated card background, and keyboard-aware. Rises
/// above the shell's tab bar so the bar never overlaps the sheet's content.
///
/// Every sheet can always be left, keyboard up or not:
///   • the **close button**, pinned in the header (it never scrolls away);
///   • a **tap on the dimmed area** — the sheet is capped so a strip at least
///     44 pt tall remains below the status bar (on any screen tall enough to
///     hold a usable sheet at all; see [_minSheetHeight]);
///   • a **swipe down** — on the header any time, and on the content when the
///     drag *starts* with the content at its top and pulls past [_dismissPull];
///   • the system back button / gesture.
/// Dragging the sheet's own content, or tapping an empty part of the sheet,
/// drops the keyboard — number pads on iPhone have no key that does.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
  // The status-bar inset, read once from the view itself. MediaQuery can't be
  // trusted for it: a `SafeArea` above the caller, and the modal route below,
  // both strip the top padding, so it reads as 0 on either side.
  final view = View.of(context);
  final topInset = view.viewPadding.top / view.devicePixelRatio;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) =>
        _Sheet(topInset: topInset, child: Builder(builder: builder)),
  );
}

/// Old name, kept so call sites migrate one at a time.
Future<T?> showGlassSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showSheet<T>(context, builder);

/// How far the content must be pulled down past its top to dismiss the sheet.
const double _dismissPull = 70;

/// Height of the dimmed strip that stays tappable above the sheet.
const double _dismissStrip = Sys.minTapTarget;

/// The smallest a sheet is ever made: its header plus a little content. On a
/// viewport too short to fit this *and* the strip (a landscape phone with the
/// keyboard up), usability of the sheet wins and the strip yields — the close
/// button in the header is still there.
const double _minSheetHeight = 120;

class _Sheet extends StatefulWidget {
  final Widget child;
  final double topInset;
  const _Sheet({required this.child, required this.topInset});

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  double _pull = 0;

  /// True when the current drag began with the content already at its top.
  /// Only such a drag may dismiss: scrolling back up to the top and carrying
  /// on must never close the sheet (and throw away a half-filled form).
  bool _armed = false;
  bool _closing = false;

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final popped = await Navigator.of(context).maybePop();
    // A vetoed pop (say, an unsaved-changes guard) must leave the sheet's
    // exits working.
    if (!popped && mounted) _closing = false;
  }

  /// Watches the sheet's own scroll view for two things the modal can't do
  /// once content scrolls: dropping the keyboard on drag, and dismissing on a
  /// pull *past the top* — an overscroll on Android (clamping physics), a
  /// negative offset on iOS (bouncing).
  bool _onScroll(ScrollNotification n) {
    // Only the sheet's own scroll view: a text field scrolling its line
    // horizontally bubbles up here too and must not drop the keyboard.
    if (n.depth != 0) return false;
    final top = n.metrics.minScrollExtent;
    if (n is ScrollStartNotification) {
      _pull = 0;
      _armed = n.dragDetails != null && n.metrics.pixels <= top;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      // Past the top (iOS bounce) counts as pull; real scrolling cancels it.
      _pull = n.metrics.pixels < top ? top - n.metrics.pixels : 0;
    } else if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      _pull -= n.overscroll;
    } else if (n is ScrollEndNotification) {
      _pull = 0;
      _armed = false;
    }
    if (_armed && _pull >= _dismissPull) _close();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // 88% of the screen at most, and never so tall that it reaches the status
    // bar: with the keyboard up the space is what's left above it.
    final maxH = math.max(
      _minSheetHeight,
      math.min(
        size.height * 0.88,
        size.height - keyboard - widget.topInset - _dismissStrip,
      ),
    );
    const radius = BorderRadius.vertical(top: Radius.circular(Sys.radiusCard));
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: sys.card,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pinned header: grabber + close. Outside the scroll view, so
                // it is always visible and a drag on it moves the sheet.
                SizedBox(
                  height: Sys.minTapTarget,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 36,
                          height: 5,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: sys.fill,
                            borderRadius:
                                BorderRadius.circular(Sys.radiusCapsule),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: 'Close',
                            child: TapTarget(
                              onTap: _close,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: sys.tertiaryFill,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close,
                                    size: 16, color: sys.secondaryLabel),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          Sys.gutter, 0, Sys.gutter, Sys.gutter + 8),
                      // A tap on an empty part of the sheet drops the keyboard.
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
