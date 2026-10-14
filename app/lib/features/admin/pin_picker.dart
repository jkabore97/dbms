import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/phone/country_codes.dart';

import '../common/osm_credit.dart';
import 'pin_preview.dart' show pinLooksMisplaced;

/// Where a business is, moved with a finger to the exact door (batch 145).
///
/// The owner: « move the pin with a finger on the map ». [PinPreview] only
/// took a tap; this map takes the pin itself — dragged, or a tap anywhere
/// puts it there — and every move goes to [onMove] at once, so the
/// latitude and longitude fields follow live. Nothing is saved here: the
/// rubrique's « Enregistrer » does that, as before.
///
/// It sits in a page that scrolls, so the gestures are shared out the way
/// a phone expects a map inside a page (Google's « cooperative » rule):
///
///  * one finger on the pin drags the pin — it claims that finger at once,
///    so the page does not move under it;
///  * one finger anywhere else scrolls the page (the map never traps it) and
///    a tap moves the pin there;
///  * two fingers move and pinch-zoom the map — the second finger claims the
///    gesture, so the page holds still;
///  * a mouse drags the map, its wheel scrolls the page, and « + » / « − »
///    zoom (the website).
///
/// The tiles are OpenStreetMap's, under their usage policy: the app's own
/// user agent, the « © OpenStreetMap » credit always on the map and linked
/// to the licence, and no bulk download (only the tiles in view, at the
/// zoom asked).
class PinPicker extends StatefulWidget {
  const PinPicker({
    super.key,
    required this.lat,
    required this.lng,
    required this.currency,
    required this.onMove,
    this.phone,
    this.onLocate,
    this.locating = false,
    this.enabled = true,
    this.tiles = true,
    this.height = 240,
  });

  /// The pin, or null when the business has no position yet: the map then
  /// opens on its country and asks for one.
  final double? lat;
  final double? lng;

  /// Where the map starts without a pin, and what [pinLooksMisplaced]
  /// judges.
  final String currency;

  /// The business's phone, in E.164: its country is where the map starts
  /// without a pin, before the currency's zone.
  final String? phone;

  final void Function(double lat, double lng) onMove;

  /// « Centrer sur ma position »: the phone's position (the screen's own
  /// _useMyPosition), drawn on the map's own buttons. Null hides it.
  final VoidCallback? onLocate;
  final bool locating;

  /// Off while the screen saves: the map shows, nothing moves the pin.
  final bool enabled;

  /// Off in widget tests, which have no network.
  final bool tiles;

  final double height;

  @override
  State<PinPicker> createState() => _PinPickerState();
}

class _PinPickerState extends State<PinPicker> {
  final _map = MapController();
  bool _ready = false;

  static const _minZoom = 2.0;
  static const _maxZoom = 19.0; // OSM's standard tiles stop at 19
  static const _streetZoom = 16.0;

  /// The pin as this map last sent it: the same pin coming back from the
  /// fields is not a reason to move the map under the finger.
  LatLng? _sent;

  /// The pin while a finger drags it, drawn from here so it follows the
  /// finger exactly (the fields keep six decimals).
  LatLng? _dragging;
  int? _pinPointer;
  Offset _grab = Offset.zero;

  /// Two fingers on the map: their positions, and the pinch's start.
  final Map<int, Offset> _touches = {};
  double _startSpan = 0;
  double _startZoom = 0;
  LatLng? _startFocus;

  /// A mouse dragging the map (the website).
  int? _mouse;
  Offset _mouseAt = Offset.zero;

  LatLng? get _pin => widget.lat == null || widget.lng == null
      ? null
      : LatLng(widget.lat!, widget.lng!);

  @override
  void dispose() {
    // Made here, so ended here: FlutterMap only disposes a controller it
    // made itself.
    _map.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PinPicker old) {
    super.didUpdateWidget(old);
    // The screen turned the map off mid-drag (« Utiliser ma position »
    // tapped with another finger, a save): the drag ends here, or its next
    // move would write over the position just found.
    if (!widget.enabled && (_dragging != null || _pinPointer != null)) {
      _dragging = null;
      _pinPointer = null;
    }
    final pin = _pin;
    if (pin == null || _dragging != null) return;
    if (old.lat == widget.lat && old.lng == widget.lng) return;
    final from = old.lat == null || old.lng == null;
    final sent = _sent;
    // Six decimals is about 10 cm: what the fields gave back of a move.
    // The first pin, even placed by a tap, brings the map in to the street.
    if (!from &&
        sent != null &&
        (sent.latitude - pin.latitude).abs() < 1e-5 &&
        (sent.longitude - pin.longitude).abs() < 1e-5) {
      return;
    }
    // A pin from elsewhere: the next one that happens to equal this map's
    // last move is still a reason to go to it.
    _sent = null;
    // Typed, located or pasted: the map goes to the new pin. Not during
    // this build — the map is a widget being built too; and not before the
    // map is ready — then it goes there as soon as it is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_ready) {
        _pending = (pin, from);
        return;
      }
      _goTo(pin, first: from);
    });
  }

  /// A pin that arrived before the map was ready.
  (LatLng, bool)? _pending;

  void _goTo(LatLng pin, {required bool first}) {
    final zoom = first
        ? _streetZoom
        : math.max(_map.camera.zoom, 14.0).toDouble();
    _map.move(pin, zoom);
  }

  void _onReady() {
    if (!mounted) return;
    setState(() => _ready = true);
    final pending = _pending;
    _pending = null;
    final pin = _pin;
    if (pending != null && pin != null) _goTo(pin, first: pending.$2);
  }

  void _send(LatLng at) {
    final lat = at.latitude.clamp(-85.0, 85.0).toDouble();
    var lng = at.longitude;
    while (lng > 180) {
      lng -= 360;
    }
    while (lng < -180) {
      lng += 360;
    }
    _sent = LatLng(lat, lng);
    widget.onMove(lat, lng);
  }

  // --- the pin, dragged ---------------------------------------------------

  void _pinDown(PointerDownEvent e) {
    if (!widget.enabled || _pinPointer != null) return;
    _pinPointer = e.pointer;
  }

  // --- the map's own pointers (raw: they take part in no gesture race) ----

  void _down(PointerDownEvent e) {
    if (!_ready || !widget.enabled) return;
    final camera = _map.camera;
    if (e.pointer == _pinPointer) {
      final pin = _pin;
      if (pin == null) {
        _pinPointer = null;
        return;
      }
      _grab = camera.latLngToScreenOffset(pin) - e.localPosition;
      setState(() => _dragging = pin);
      return;
    }
    if (e.kind == PointerDeviceKind.mouse) {
      if (e.buttons & kPrimaryMouseButton != 0) {
        _mouse = e.pointer;
        _mouseAt = e.localPosition;
      }
      return;
    }
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) _startPinch();
  }

  void _startPinch() {
    final camera = _map.camera;
    final points = _touches.values.toList();
    final focus = (points[0] + points[1]) / 2;
    _startSpan = (points[0] - points[1]).distance;
    _startZoom = camera.zoom;
    _startFocus = camera.screenOffsetToLatLng(focus);
  }

  void _moveTo(PointerMoveEvent e) {
    if (!_ready) return;
    final camera = _map.camera;
    if (e.pointer == _pinPointer && _dragging != null) {
      if (!widget.enabled) return;
      final at = camera.screenOffsetToLatLng(e.localPosition + _grab);
      setState(() => _dragging = at);
      _send(at);
      return;
    }
    if (e.pointer == _mouse) {
      final delta = e.localPosition - _mouseAt;
      _mouseAt = e.localPosition;
      final centre = camera.crs.latLngToOffset(camera.center, camera.zoom);
      _map.move(
        camera.crs.offsetToLatLng(centre - delta, camera.zoom),
        camera.zoom,
      );
      return;
    }
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    final focusAt = _startFocus;
    if (_touches.length != 2 || focusAt == null || _startSpan <= 0) return;
    final points = _touches.values.toList();
    final focus = (points[0] + points[1]) / 2;
    final span = (points[0] - points[1]).distance;
    final zoom = (_startZoom + math.log(span / _startSpan) / math.ln2)
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    // The place under the fingers stays under the fingers.
    final under = camera.crs.latLngToOffset(focusAt, zoom);
    final centre = under - (focus - camera.nonRotatedSize.center(Offset.zero));
    _map.move(camera.crs.offsetToLatLng(centre, zoom), zoom);
  }

  void _up(PointerEvent e) {
    if (e.pointer == _pinPointer) {
      _pinPointer = null;
      if (_dragging != null) setState(() => _dragging = null);
    }
    if (e.pointer == _mouse) _mouse = null;
    if (_touches.remove(e.pointer) != null) {
      _startFocus = null;
      if (_touches.length == 2) _startPinch();
    }
  }

  void _zoom(double by) {
    if (!_ready) return;
    final camera = _map.camera;
    _map.move(
      camera.center,
      (camera.zoom + by).clamp(_minZoom, _maxZoom).toDouble(),
    );
  }

  void _tapUp(TapUpDetails d) {
    if (!_ready || !widget.enabled) return;
    _send(_map.camera.screenOffsetToLatLng(d.localPosition));
  }

  /// The finger on the pin is the pin's from the first touch: neither the
  /// page nor the map's tap gets it. Off, the pin lets the page scroll.
  Widget _pinBox() => Listener(
    key: const Key('pin-picker-pin'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: _pinDown,
    child: RawGestureDetector(
      gestures: !widget.enabled
          ? const {}
          : {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                    (_) {},
                  ),
            },
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.grab : MouseCursor.defer,
      ),
    ),
  );

  // ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pin = _dragging ?? _pin;
    final start = pin == null
        ? startView(phone: widget.phone, currency: widget.currency)
        : null;
    final misplaced =
        pin != null &&
        pinLooksMisplaced(pin.latitude, pin.longitude, widget.currency);
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            key: const Key('pin-picker-map'),
            height: widget.height,
            child: RawGestureDetector(
              // The map itself takes no pointer (IgnorePointer below): its
              // own recognizers — a long press, a scale, a tap — would join
              // the page's gesture race, and a finger held still for half a
              // second then claimed the page's scroll (145, seen on the
              // web). Every gesture is this widget's own.
              behavior: HitTestBehavior.opaque,
              gestures: {
                _TwoFingers: GestureRecognizerFactoryWithHandlers<_TwoFingers>(
                  () => _TwoFingers(debugOwner: this),
                  (_) {},
                ),
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      () => TapGestureRecognizer(debugOwner: this),
                      (t) => t.onTapUp = _tapUp,
                    ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _moveTo,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: pin ?? LatLng(start!.lat, start.lng),
                            initialZoom: pin == null
                                ? start!.zoom
                                : _streetZoom,
                            minZoom: _minZoom,
                            maxZoom: _maxZoom,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                            onMapReady: _onReady,
                            // The pin's hit box follows the camera.
                            onPositionChanged: (_, _) {
                              if (mounted) setState(() {});
                            },
                          ),
                          children: [
                            if (widget.tiles)
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'bf.kaj.app',
                                maxNativeZoom: 19,
                              )
                            else
                              const _Paper(),
                            if (pin != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: pin,
                                    width: 56,
                                    height: 56,
                                    alignment: Alignment.topCenter,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: AnimatedScale(
                                        scale: _dragging != null ? 1.2 : 1,
                                        alignment: Alignment.bottomCenter,
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        child: Icon(
                                          Icons.location_on,
                                          size: 48,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    // The pin's hit box, over the map, where the marker is
                    // drawn: laid out after the map, so it reads the camera
                    // of this very layout.
                    if (pin != null && _ready)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, _) {
                            final at = _map.camera.latLngToScreenOffset(pin);
                            return Stack(
                              children: [
                                Positioned(
                                  left: at.dx - 28,
                                  top: at.dy - 56,
                                  width: 56,
                                  height: 56,
                                  child: _pinBox(),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Buttons(
                        onZoomIn: () => _zoom(1),
                        onZoomOut: () => _zoom(-1),
                        onLocate: widget.enabled ? widget.onLocate : null,
                        showLocate: widget.onLocate != null,
                        locating: widget.locating,
                      ),
                    ),
                    const Positioned(right: 0, bottom: 0, child: OsmCredit()),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (pin == null)
          Text(
            context.tr(
              'Pas encore de position : touchez la carte à l\'endroit de la porte pour y placer le repère.',
            ),
            key: const Key('pin-picker-place'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            context.tr(
              'Faites glisser le repère jusqu\'à la porte, ou touchez la carte à cet endroit.',
            ),
            style: hint,
          ),
        const SizedBox(height: 2),
        Text(
          context.tr(
            'Deux doigts (ou la souris) déplacent la carte ; pincez ou utilisez + et − pour zoomer.',
          ),
          style: hint,
        ),
        if (misplaced) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('pin-picker-misplaced'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                      'Cette position est loin de la zone de votre monnaie. Si le téléphone n\'était pas sur place, faites glisser le repère au bon endroit ou collez le lien Google Maps.',
                    ),
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Where the map opens with no pin yet: the country of the business's
/// phone (when it is inside the currency's zone), else the currency's
/// zone, else the whole world.
({double lat, double lng, double zoom}) startView({
  String? phone,
  required String currency,
}) {
  // Only a number that names its country: « 70 00 00 00 » says nothing.
  var number = (phone ?? '').replaceAll(RegExp(r'[\s\-().]'), '');
  if (number.startsWith('00')) number = '+${number.substring(2)}';
  final iso = number.startsWith('+') ? countryOfNumber(number)?.iso : null;
  final country = iso == null ? null : _countries[iso];
  final zone = _zones[currency];
  // A phone from abroad (a Paris number for a franc CFA shop) does not
  // send the map out of the currency's zone.
  if (country != null &&
      (zone == null ||
          !pinLooksMisplaced(country.lat, country.lng, currency))) {
    return country;
  }
  return zone ?? _world;
}

const _world = (lat: 15.0, lng: 0.0, zoom: 2.0);

/// A country's middle and a zoom that shows all of it in a 240 px map.
const _countries = <String, ({double lat, double lng, double zoom})>{
  'BF': (lat: 12.24, lng: -1.56, zoom: 6),
  'CI': (lat: 7.54, lng: -5.55, zoom: 6),
  'ML': (lat: 17.0, lng: -4.0, zoom: 4.5),
  'NE': (lat: 17.0, lng: 8.5, zoom: 4.5),
  'SN': (lat: 14.4, lng: -14.6, zoom: 6),
  'TG': (lat: 8.6, lng: 0.9, zoom: 6),
  'BJ': (lat: 9.3, lng: 2.3, zoom: 6),
  'GW': (lat: 11.9, lng: -15.2, zoom: 7),
  'GH': (lat: 7.9, lng: -1.0, zoom: 6),
  'NG': (lat: 9.1, lng: 8.7, zoom: 5),
  'GN': (lat: 10.0, lng: -10.9, zoom: 6),
  'GM': (lat: 13.45, lng: -15.4, zoom: 7),
  'MR': (lat: 20.3, lng: -10.3, zoom: 4.5),
  'CM': (lat: 6.5, lng: 12.4, zoom: 5),
  'GA': (lat: -0.6, lng: 11.6, zoom: 6),
  'CG': (lat: -0.7, lng: 15.2, zoom: 5),
  'CD': (lat: -2.9, lng: 23.6, zoom: 4),
  'GQ': (lat: 1.6, lng: 10.4, zoom: 7),
  'MA': (lat: 31.8, lng: -7.1, zoom: 5),
  'FR': (lat: 46.6, lng: 2.4, zoom: 5),
  'BE': (lat: 50.6, lng: 4.6, zoom: 7),
  'GB': (lat: 54.0, lng: -2.5, zoom: 5),
  'US': (lat: 39.8, lng: -98.6, zoom: 3),
  'CA': (lat: 56.0, lng: -96.0, zoom: 2.5),
};

/// A currency's zone, when the phone says nothing.
const _zones = <String, ({double lat, double lng, double zoom})>{
  'XOF': (lat: 12.0, lng: -4.0, zoom: 4), // UEMOA
  'XAF': (lat: 3.5, lng: 15.0, zoom: 4), // CEMAC
  'GHS': (lat: 7.9, lng: -1.0, zoom: 6),
  'NGN': (lat: 9.1, lng: 8.7, zoom: 5),
  'EUR': (lat: 48.5, lng: 9.0, zoom: 3.5),
};

/// Claims a gesture once a second finger is on the map, so a pinch moves
/// the map and not the page. With one finger it never claims: the page's
/// scroll and the map's tap race as they always did.
class _TwoFingers extends OneSequenceGestureRecognizer {
  _TwoFingers({super.debugOwner});

  final Set<int> _down = {};
  bool _won = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.kind != PointerDeviceKind.mouse && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _down.add(event.pointer);
    if (_down.length >= 2) {
      _won = true;
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _down.remove(event.pointer);
      // A lone finger lifted: out of the race, so its tap is the map's.
      if (!_won) resolvePointer(event.pointer, GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _down.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _won = false;
    _down.clear();
  }

  @override
  String get debugDescription => 'two fingers on the map';
}

/// « + », « − » and « Centrer sur ma position », over the map's corner.
class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocate,
    required this.showLocate,
    required this.locating,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onLocate;
  final bool showLocate;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget button(String tip, Widget icon, VoidCallback? onTap, Key key) =>
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            key: key,
            tooltip: tip,
            padding: EdgeInsets.zero,
            iconSize: 22,
            onPressed: onTap,
            icon: icon,
          ),
        );
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            context.tr('Zoomer'),
            const Icon(Icons.add),
            onZoomIn,
            const Key('pin-picker-zoom-in'),
          ),
          button(
            context.tr('Dézoomer'),
            const Icon(Icons.remove),
            onZoomOut,
            const Key('pin-picker-zoom-out'),
          ),
          if (showLocate)
            button(
              context.tr('Centrer sur ma position'),
              locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              locating ? null : onLocate,
              const Key('pin-picker-locate'),
            ),
        ],
      ),
    );
  }
}

/// Without tiles (tests): a plain grid, so a moved pin shows it moved.
class _Paper extends StatelessWidget {
  const _Paper();

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return IgnorePointer(
      child: CustomPaint(painter: _Grid(line), size: Size.infinite),
    );
  }
}

class _Grid extends CustomPainter {
  _Grid(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Grid old) => old.color != color;
}
