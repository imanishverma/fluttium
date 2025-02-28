import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Action;
import 'package:fluttium/fluttium.dart';
import 'package:fluttium_interfaces/fluttium_interfaces.dart';
import 'package:fluttium_protocol/fluttium_protocol.dart';

/// {@template tester}
/// The tester that is used to execute the actions in a flow file.
/// {@endtemplate}
class Tester {
  /// {@macro tester}
  Tester(this._binding, this._registry, {Emitter? emitter})
      : _emitter = emitter ?? Emitter();

  final Emitter _emitter;

  final WidgetsBinding _binding;

  final Registry _registry;

  SemanticsOwner get _semanticsOwner => _binding.pipelineOwner.semanticsOwner!;

  /// The current screen's media query information.
  MediaQueryData get mediaQuery => MediaQueryData.fromWindow(_binding.window);

  /// Converts the [steps] into a list of executable actions.
  Future<List<Future<void> Function()>> convert(
    List<UserFlowStep> steps,
  ) async {
    return Future.wait(
      steps.map((step) async {
        try {
          final action = _registry.getAction(step.actionName, step.arguments);
          final actionRepresentation = action.description();
          await _emitter.announce(actionRepresentation);

          return () async {
            try {
              await _emitter.start(actionRepresentation);
              if (await action.execute(this)) {
                return _emitter.done(actionRepresentation);
              }
              return _emitter.fail(actionRepresentation);
            } catch (err) {
              return _emitter.fail(actionRepresentation, reason: '$err');
            }
          };
        } catch (err) {
          await _emitter.fatal('$err');
          rethrow;
        }
      }).toList(),
    );
  }

  /// Store binary data with the given [fileName].
  Future<void> storeFile(String fileName, Uint8List bytes) async {
    await _emitter.store(fileName, bytes);
  }

  /// Dispatch an event to the targets found by a hit test on its position.
  void emitPointerEvent(PointerEvent event) {
    return _binding.handlePointerEvent(event);
  }

  /// Dispatch a message to the platform.
  Future<void> emitPlatformMessage(String channel, ByteData? data) async {
    await _binding.defaultBinaryMessenger.handlePlatformMessage(
      channel,
      data,
      (ByteData? data) {},
    );
  }

  /// Pump the widget tree for the given [duration].
  ///
  /// If [duration] is null, it will pump for a single frame.
  Future<void> pump({Duration? duration}) async {
    if (duration == null) {
      return _binding.endOfFrame;
    }

    final end = clock.now().add(duration);
    while (clock.now().isBefore(end)) {
      await _binding.endOfFrame;
    }
  }

  /// Pump the widget tree and wait for animations to complete.
  Future<void> pumpAndSettle({Duration? timeout}) async {
    final end = clock.now().add(timeout ?? const Duration(seconds: 10));
    do {
      if (clock.now().isAfter(end)) {
        throw Exception('pumpAndSettle timed out');
      }
      await pump();
    } while (_binding.hasScheduledFrame);
  }

  /// Find a node that matches the given text.
  ///
  /// The [text] can be a [String] that can also be used as a [RegExp].
  Future<SemanticsNode?> find(String text, {Duration? timeout}) async {
    var nodes = _findNodes(_semanticsOwner.rootSemanticsNode!, text);

    final end = clock.now().add(timeout ?? const Duration(seconds: 10));
    while (nodes.isEmpty) {
      await pump();
      if (clock.now().isAfter(end)) {
        return null;
      }
      nodes = _findNodes(_semanticsOwner.rootSemanticsNode!, text);
    }

    return nodes.first;
  }

  List<SemanticsNode> _findNodes(SemanticsNode node, String text) {
    final nodes = <SemanticsNode>[];
    node.visitChildren((n) {
      // Add all descendants that match the pattern.
      if (!n.mergeAllDescendantsIntoThisNode) {
        nodes.addAll(_findNodes(n, text));
      }

      // If the node is invisible or has the hidden flag, don't add it.
      if (n.isInvisible || n.hasFlag(SemanticsFlag.isHidden)) {
        return true;
      }

      // Check if the current node matches the pattern on any semantic values.
      // If it does, add it to the list.
      final data = n.getSemanticsData();
      if ([
        data.label,
        data.value,
        data.hint,
        data.tooltip,
      ].any((value) => value == text || RegExp('^$text\$').hasMatch(value))) {
        nodes.add(n);
      }

      return true;
    });

    return nodes;
  }

  /// Retrieve the root repaint boundary.
  RenderRepaintBoundary? getRenderRepaintBoundary() {
    final renderObject = _binding.renderViewElement!.renderObject!;
    RenderRepaintBoundary? boundary;
    void find(RenderObject element) {
      if (boundary != null) return;

      if (element is! RenderRepaintBoundary) {
        return element.visitChildren(find);
      }
      boundary = element;
    }

    if (renderObject is! RenderRepaintBoundary) {
      renderObject.visitChildren(find);
    }
    return boundary;
  }
}
