import 'package:flutter/widgets.dart';

/// The business's bell takes the last place of a tool page's top bar
/// (PageBell, 115) by moving the page's actions one place left with
/// AppBarTheme.actionsPadding — and Flutter applies that padding only to a
/// bar that has actions. So every AppBar ends its actions with this
/// zero-width one: a page with no button of its own (or none for this
/// person) still keeps its title out from under the bell. Outside a
/// business, where nothing pads the actions, it is nothing at all.
const Widget bellRoom = SizedBox.shrink(key: Key('bell-room'));
