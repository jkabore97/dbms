import 'package:flutter/widgets.dart';

import 'live_card_io.dart' if (dart.library.js_interop) 'live_card_web.dart' as impl;

/// The card itself (177): the guests' page at [uri], live — an animated
/// card moves — drawn over [placeholder] (its still picture) once loaded.
/// Not touched: the page lays it under its own « open the card » tap. Where
/// no web view can be drawn (the tests), the placeholder alone.
Widget liveCard({required Uri uri, required Widget placeholder, Key? key}) =>
    impl.liveCard(uri: uri, placeholder: placeholder, key: key);
