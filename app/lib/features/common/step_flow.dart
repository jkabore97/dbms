import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../home/business_frame.dart';

/// One entry at a time (115): the shared full-screen step flow every
/// « Vente », « Ajouter un article », « Service », « Facture », « Dépense »…
/// is built on.
///
/// One question per screen, big touch targets, a step bar at the top,
/// « Suivant » (disabled until the step is valid), a last screen that is a
/// summary with « Enregistrer », then « C'est fait » with the next useful
/// thing to do. Back is the previous step; back on the first step — or the
/// cross — asks « Quitter sans enregistrer ? » when something was entered.
/// The answers are kept on the device while the flow is open ([FlowDraft]):
/// a call, a dead battery or a killed app comes back to the same step.
///
/// The flow is a route pushed over the business's pages ([StepFlow.push]):
/// it covers the bar as a sheet does (108's BusinessCover), it is closed by
/// Android's or the browser's back step by step (114's BackFirst pops it as
/// any route, this page's PopScope turns that into « previous step »), and
/// on a wide screen it stands in the middle, phone-wide.
///
/// The owner keeps the answers. A flow is a StatefulWidget whose `build`
/// returns a [StepFlow] with its [FlowStep]s, rebuilt on every setState —
/// the steps are closures over the owner's fields:
///
/// ```dart
/// return StepFlow(
///   title: context.tr('Dépense'),
///   draft: FlowDraft(key: 'expense:${org.id}', save: _toJson, restore: _fromJson),
///   steps: [
///     FlowStep(id: 'amount', title: context.tr('Combien ?'),
///         isValid: () => _amount > 0, builder: (_) => AmountField(...)),
///     ...
///   ],
///   summary: (_) => FlowSummary(rows: [...]),
///   onSave: _save,              // true: saved — false: stay, quietly
///   done: (_) => FlowDone(message: ..., actions: [...]),
/// );
/// ```
///
/// Writing stays the owner's, through the server functions that exist —
/// and their offline paths (the outbox) exactly as before.
class StepFlow extends StatefulWidget {
  const StepFlow({
    super.key,
    required this.title,
    required this.steps,
    required this.summary,
    required this.onSave,
    required this.done,
    this.summaryTitle,
    this.saveLabel,
    this.draft,
    this.isDirty,
    this.controller,
    this.store,
  });

  /// The flow's name, in the bar at the top: « Vente », « Nouvel article ».
  final String title;

  /// The questions, in order. A step whose [FlowStep.shown] says no is not
  /// drawn nor counted.
  final List<FlowStep> steps;

  /// The last screen before saving: what will be written, in full.
  final WidgetBuilder summary;

  /// The summary's question. « Vérifiez avant d'enregistrer » by default.
  final String? summaryTitle;

  /// The summary's button. « Enregistrer » by default.
  final String? saveLabel;

  /// Writes. True: saved, the flow shows [done]. False: nothing written and
  /// nothing to say (a payment sheet dismissed) — the summary stays. A throw
  /// is said in French under the button, and the summary stays.
  final Future<bool> Function() onSave;

  /// « C'est fait »: what was saved and what to do next ([FlowDone]).
  final WidgetBuilder done;

  /// Kept on the device while the flow is open. Null: nothing is kept.
  final FlowDraft? draft;

  /// Something entered that leaving would lose. By default: any step past
  /// the first, or an answer on the first that differs from how the flow
  /// opened (read through [draft]).
  final bool Function()? isDirty;

  /// For the owner: start again after « C'est fait » (« Ajouter un autre »),
  /// go back to a step from the summary (« Modifier »).
  final StepFlowController? controller;

  /// Where the draft is kept. By default the device's own preferences
  /// (AppScope's LocalDb); a test hands its own.
  final FlowStore? store;

  /// Opens [flow] over the pages, full screen. Resolves with what the flow
  /// closed with: true once something was saved (even if the person then
  /// started another and left it), as the sheets it replaces.
  static Future<bool?> push(BuildContext context, Widget flow) =>
      Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => flow,
      ));

  @override
  State<StepFlow> createState() => _StepFlowState();
}

/// One question of a [StepFlow].
class FlowStep {
  const FlowStep({
    required this.id,
    required this.title,
    required this.builder,
    this.help,
    this.isValid,
    this.shown,
    this.optional = false,
  });

  /// Stable: the draft remembers the step by it, tests find it by
  /// `Key('flow-step-<id>')`, the summary's « Modifier » goes back to it.
  final String id;

  /// The question, large: « Quel article ? », « Combien ? ».
  final String title;

  /// One line under it, when the question needs one.
  final String? help;

  /// The answer: tiles, a field, a keypad.
  final WidgetBuilder builder;

  /// « Suivant » is enabled only while this says yes. Null: always.
  final bool Function()? isValid;

  /// Drawn at all? Null: always. A step that depends on an earlier answer
  /// (the customer's name only for a credit) says no otherwise.
  final bool Function()? shown;

  /// « (facultatif) » under the question; « Suivant » works empty.
  final bool optional;
}

/// What « C'est fait » says and offers.
class FlowDone extends StatelessWidget {
  const FlowDone({
    super.key,
    required this.message,
    this.details,
    this.actions = const [],
  });

  /// « Vente enregistrée », « Savon ajouté ».
  final String message;

  /// Under it: a total, a receipt, a line about the network.
  final Widget? details;

  /// The next useful things: « Partager le reçu sur WhatsApp »,
  /// « Nouvelle vente », « Ajouter un autre ». « Terminé » is always there.
  final List<FlowAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(context.tr('C\'est fait'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(message,
            key: const Key('flow-done-message'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium),
        if (details != null) ...[const SizedBox(height: 16), details!],
        const SizedBox(height: 24),
        for (final a in actions) ...[
          SizedBox(
            height: 56,
            child: a.primary
                ? FilledButton.icon(
                    key: a.key,
                    onPressed: a.onPressed,
                    icon: Icon(a.icon),
                    label: Text(a.label, style: const TextStyle(fontSize: 17)),
                  )
                : OutlinedButton.icon(
                    key: a.key,
                    onPressed: a.onPressed,
                    icon: Icon(a.icon),
                    label: Text(a.label, style: const TextStyle(fontSize: 17)),
                  ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// A button of « C'est fait ».
class FlowAction {
  const FlowAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final Key? key;
}

/// The summary's lines: label on the left, the answer on the right, and a
/// « Modifier » that goes back to the step it came from.
class FlowSummary extends StatelessWidget {
  const FlowSummary({super.key, required this.rows, this.footer});

  final List<FlowSummaryRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(r.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(r.value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight:
                              r.bold ? FontWeight.bold : FontWeight.w500)),
                ),
                if (r.step != null)
                  Builder(
                    builder: (context) => IconButton(
                      key: Key('flow-edit-${r.step}'),
                      tooltip: context.tr('Modifier'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => StepFlowScope.of(context)?.goTo(r.step!),
                    ),
                  ),
              ],
            ),
          ),
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ],
    );
  }
}

class FlowSummaryRow {
  const FlowSummaryRow(this.label, this.value, {this.step, this.bold = false});

  final String label;
  final String value;

  /// The step « Modifier » goes back to; null draws no pencil.
  final String? step;
  final bool bold;
}

/// A big choice: one of a few answers, a whole-width tile each.
class FlowChoice<T> extends StatelessWidget {
  const FlowChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<FlowOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in options) ...[
          Material(
            color: o.value == value
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: o.value == value
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('flow-option-${o.value}'),
              onTap: () => onChanged(o.value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      if (o.icon != null) ...[
                        Icon(o.icon, size: 28),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(o.label,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            if (o.detail != null)
                              Text(o.detail!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (o.value == value)
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class FlowOption<T> {
  const FlowOption(this.value, this.label, {this.icon, this.detail});

  final T value;
  final String label;
  final IconData? icon;
  final String? detail;
}

/// A number typed big: an amount, a quantity. The keyboard is the phone's
/// own numeric one; commas are read as points.
class FlowNumberField extends StatelessWidget {
  const FlowNumberField({
    super.key,
    required this.controller,
    this.onChanged,
    this.suffix,
    this.hint,
    this.decimal = true,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? suffix;
  final String? hint;
  final bool decimal;
  final bool autofocus;

  /// The number in [c], or null when empty or not a number.
  static double? read(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: Theme.of(context)
            .textTheme
            .headlineMedium
            ?.copyWith(fontWeight: FontWeight.bold),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
      );
}

/// Kept on the device while the flow is open: [save] turns the owner's
/// answers into JSON, [restore] puts them back. Cleared once saved, or when
/// the person leaves on purpose.
class FlowDraft {
  const FlowDraft({required this.key, required this.save, required this.restore});

  /// One per flow and business: `sale:<orgId>`.
  final String key;
  final Map<String, Object?> Function() save;

  /// Puts [answers] back. A key that is missing is that answer's default —
  /// so `restore(const {})` empties the flow (« Tout effacer »).
  final void Function(Map<String, Object?> answers) restore;
}

/// Where drafts live. The device's preferences by default.
abstract class FlowStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class _PrefStore implements FlowStore {
  _PrefStore(this._scope);
  final AppScope _scope;
  @override
  Future<String?> read(String key) => _scope.db.readPref(key);
  @override
  Future<void> write(String key, String? value) =>
      _scope.db.writePref(key, value);
}

/// For tests and for a flow kept only in memory.
class MemoryFlowStore implements FlowStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// The owner's handle on its flow.
class StepFlowController {
  _StepFlowState? _state;

  /// Back to the first step, the draft forgotten — after « C'est fait »,
  /// once the owner has emptied its answers (« Ajouter un autre »).
  void restart() => _state?._restart();

  /// To the step [id] (the summary's « Modifier »).
  void goTo(String id) => _state?._goTo(id);

  /// The draft written now (an owner changing answers outside a step).
  void keep() => _state?._keepDraft();
}

/// Read by widgets inside a flow (FlowSummary's « Modifier »).
class StepFlowScope extends InheritedWidget {
  const StepFlowScope({super.key, required this.controller, required super.child});

  final StepFlowController controller;

  static StepFlowController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StepFlowScope>()?.controller;

  @override
  bool updateShouldNotify(StepFlowScope oldWidget) =>
      controller != oldWidget.controller;
}

enum _Phase { steps, summary, done }

class _StepFlowState extends State<StepFlow> with WidgetsBindingObserver {
  late final StepFlowController _controller =
      widget.controller ?? StepFlowController();

  /// The id of the step on screen (ids, not indexes: a step that comes or
  /// goes with an answer never moves the person elsewhere).
  String? _stepId;
  _Phase _phase = _Phase.steps;
  bool _busy = false;
  String? _error;
  bool _resumed = false;
  FlowStore? _store;
  bool _draftRead = false;

  List<FlowStep> get _shown =>
      [for (final s in widget.steps) if (s.shown?.call() ?? true) s];

  int get _index {
    final shown = _shown;
    final i = shown.indexWhere((s) => s.id == _stepId);
    if (i >= 0) return i;
    // The step on screen is no longer shown: the nearest one before it.
    final all = widget.steps.indexWhere((s) => s.id == _stepId);
    for (var j = all - 1; j >= 0; j--) {
      final k = shown.indexWhere((s) => s.id == widget.steps[j].id);
      if (k >= 0) return k;
    }
    return 0;
  }

  /// The answers as the flow opened (empty), to tell « something typed ».
  String? _pristine;

  String? _answers() {
    try {
      final draft = widget.draft;
      return draft == null ? null : jsonEncode(draft.save());
    } catch (_) {
      return null;
    }
  }

  bool get _dirty =>
      _phase != _Phase.done &&
      (widget.isDirty?.call() ??
          (_phase == _Phase.summary ||
              _index > 0 ||
              (_pristine != null && _answers() != _pristine)));

  @override
  void initState() {
    super.initState();
    _controller._state = this;
    WidgetsBinding.instance.addObserver(this);
    _pristine = _answers();
    final shown = _shown;
    _stepId = shown.isEmpty ? null : shown.first.id;
    if (shown.isEmpty) _phase = _Phase.summary;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftRead) return;
    _draftRead = true;
    final scope = AppScope.maybeOf(context);
    _store = widget.store ?? (scope == null ? null : _PrefStore(scope));
    _readDraft();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_controller._state == this) _controller._state = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app (a call, the camera, the battery): what was typed on
    // this step is kept too, not only what was passed.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _keepDraft();
    }
  }

  String? get _draftKey {
    final key = widget.draft?.key;
    return key == null ? null : 'step_flow:$key';
  }

  Future<void> _readDraft() async {
    final draft = widget.draft;
    final key = _draftKey;
    final store = _store;
    if (draft == null || key == null || store == null) return;
    try {
      final raw = await store.read(key);
      if (raw == null || !mounted) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      final answers = map['answers'];
      if (answers is Map) {
        draft.restore(Map<String, Object?>.from(answers));
      }
      if (!mounted) return;
      setState(() {
        final step = map['step'];
        if (map['phase'] == 'summary') {
          _phase = _Phase.summary;
        } else if (step is String &&
            widget.steps.any((s) => s.id == step)) {
          _stepId = step;
        }
        _resumed = true;
      });
    } catch (_) {
      // A draft that cannot be read is a fresh start, never a crash.
    }
  }

  Future<void> _keepDraft() async {
    final draft = widget.draft;
    final key = _draftKey;
    final store = _store;
    if (draft == null || key == null || store == null) return;
    if (_phase == _Phase.done) return;
    try {
      await store.write(
          key,
          jsonEncode({
            'step': _stepId,
            'phase': _phase == _Phase.summary ? 'summary' : 'steps',
            'answers': draft.save(),
          }));
    } catch (_) {}
  }

  Future<void> _forgetDraft() async {
    final key = _draftKey;
    final store = _store;
    if (key == null || store == null) return;
    try {
      await store.write(key, null);
    } catch (_) {}
  }

  void _next() {
    final shown = _shown;
    final i = _index;
    if (_phase != _Phase.steps || shown.isEmpty) return;
    final step = shown[i];
    if (!(step.isValid?.call() ?? true)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      // Shown again after this answer: a later step may have come or gone.
      final after = _shown;
      final at = after.indexWhere((s) => s.id == step.id);
      if (at + 1 < after.length) {
        _stepId = after[at + 1].id;
      } else {
        _phase = _Phase.summary;
      }
    });
    _keepDraft();
  }

  /// Back: the previous step; on the first, leave (asking if anything
  /// would be lost). After « C'est fait », close.
  Future<void> _back() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_phase == _Phase.done) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_phase == _Phase.summary) {
      final shown = _shown;
      if (shown.isNotEmpty) {
        setState(() {
          _phase = _Phase.steps;
          _stepId = shown.last.id;
          _error = null;
        });
        _keepDraft();
        return;
      }
    } else if (_index > 0) {
      setState(() {
        _stepId = _shown[_index - 1].id;
        _error = null;
      });
      _keepDraft();
      return;
    }
    await _leave();
  }

  Future<void> _leave() async {
    if (_dirty && !await UnsavedInput.askLeave(context)) return;
    await _forgetDraft();
    // Something saved earlier in this flow (« Ajouter un autre », « Nouvelle
    // vente ») still tells the page underneath to read itself again.
    if (mounted) Navigator.of(context).pop(_savedOnce);
  }

  /// True once a save went through, even if the person started another.
  bool _savedOnce = false;

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave();
      if (!mounted) return;
      if (saved) {
        _savedOnce = true;
        await _forgetDraft();
        if (!mounted) return;
        setState(() => _phase = _Phase.done);
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restart() {
    _forgetDraft();
    setState(() {
      final shown = _shown;
      _phase = shown.isEmpty ? _Phase.summary : _Phase.steps;
      _stepId = shown.isEmpty ? null : shown.first.id;
      _error = null;
      _resumed = false;
    });
  }

  void _goTo(String id) {
    if (!_shown.any((s) => s.id == id)) return;
    setState(() {
      _phase = _Phase.steps;
      _stepId = id;
      _error = null;
    });
    _keepDraft();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    final i = _index;
    final step = _phase == _Phase.steps && shown.isNotEmpty ? shown[i] : null;
    final total = shown.length + 1; // the summary counts as the last step
    final at = _phase == _Phase.steps ? i + 1 : total;
    final valid = step == null || (step.isValid?.call() ?? true);

    final String question;
    if (_phase == _Phase.done) {
      question = '';
    } else if (step != null) {
      question = step.title;
    } else {
      question = widget.summaryTitle ?? context.tr('Vérifiez avant d\'enregistrer');
    }

    final body = switch (_phase) {
      _Phase.done => KeyedSubtree(
          key: const Key('flow-done'), child: widget.done(context)),
      _Phase.summary => KeyedSubtree(
          key: const Key('flow-summary'), child: widget.summary(context)),
      _Phase.steps => KeyedSubtree(
          key: Key('flow-step-${step!.id}'), child: step.builder(context)),
    };

    final Widget button;
    if (_phase == _Phase.done) {
      button = FilledButton(
        key: const Key('flow-finish'),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(context.tr('Terminé'), style: const TextStyle(fontSize: 18)),
      );
    } else if (_phase == _Phase.summary) {
      button = FilledButton.icon(
        key: const Key('flow-save'),
        onPressed: _busy ? null : _save,
        icon: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check),
        label: Text(widget.saveLabel ?? context.tr('Enregistrer'),
            style: const TextStyle(fontSize: 18)),
      );
    } else {
      button = FilledButton(
        key: const Key('flow-next'),
        onPressed: valid ? _next : null,
        child: Text(context.tr('Suivant'), style: const TextStyle(fontSize: 18)),
      );
    }

    return StepFlowScope(
      controller: _controller,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: UnsavedInput(
          isDirty: () => _dirty,
          child: Scaffold(
            appBar: AppBar(
              leading: _phase == _Phase.done
                  ? const SizedBox.shrink()
                  : IconButton(
                      key: const Key('flow-back'),
                      tooltip: context.tr('Retour'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _busy ? null : _back,
                    ),
              title: Text(widget.title),
              actions: [
                if (_phase != _Phase.done)
                  IconButton(
                    key: const Key('flow-close'),
                    tooltip: context.tr('Fermer'),
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : _leave,
                  ),
              ],
              bottom: _phase == _Phase.done
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(28),
                      child: _StepBar(at: at, total: total),
                    ),
            ),
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                          children: [
                            if (_resumed && _phase != _Phase.done) ...[
                              _ResumedBanner(onRestart: () {
                                // An empty map: the owner's answers back to
                                // their defaults (see [FlowDraft.restore]).
                                widget.draft?.restore(const {});
                                _restart();
                              }),
                              const SizedBox(height: 16),
                            ],
                            if (question.isNotEmpty)
                              Text(question,
                                  key: const Key('flow-question'),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                            if (step?.help != null) ...[
                              const SizedBox(height: 6),
                              Text(step!.help!,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ],
                            if (step?.optional ?? false) ...[
                              const SizedBox(height: 4),
                              Text(context.tr('(facultatif)'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ],
                            if (question.isNotEmpty) const SizedBox(height: 20),
                            body,
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Text(_error!,
                                  key: const Key('flow-error'),
                                  style: TextStyle(
                                      color: theme.colorScheme.error)),
                              const SizedBox(height: 8),
                            ],
                            SizedBox(height: 56, child: button),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Étape 2 sur 5 » and one segment per step.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.at, required this.total});

  final int at;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('flow-step-bar'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                for (var s = 1; s <= total; s++) ...[
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: s <= at
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (s < total) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(context.tr('Étape {at} sur {total}', {'at': at, 'total': total}),
              style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ResumedBanner extends StatelessWidget {
  const _ResumedBanner({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('flow-resumed'),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(context.tr('Nous avons repris là où vous étiez.'))),
          TextButton(
            key: const Key('flow-start-over'),
            onPressed: onRestart,
            child: Text(context.tr('Tout effacer')),
          ),
        ],
      ),
    );
  }
}
