import 'dart:async';

import 'package:dio/dio.dart';

/// Tracks short-lived typing presence only while the conversation is visible.
class ConversationTypingSession {
  ConversationTypingSession({
    required this.readPeer,
    required this.setTyping,
    required this.isCurrent,
    required this.onPeerChanged,
  });

  final Future<bool> Function() readPeer;
  final Future<void> Function(bool typing) setTyping;
  final bool Function() isCurrent;
  final void Function(bool typing) onPeerChanged;

  static const _pollInterval = Duration(milliseconds: 1250);
  static const _idleInterval = Duration(seconds: 2);
  static const _pulseInterval = Duration(seconds: 2);
  static const _peerExpiry = Duration(seconds: 5);

  Timer? _poll;
  Timer? _idle;
  Timer? _peerExpires;
  Timer? _pulse;
  Future<void> _writes = Future.value();
  bool _active = false;
  bool _localTyping = false;
  bool _advertised = false;
  bool _peerTyping = false;
  bool _unsupported = false;
  int _generation = 0;

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _generation++;
    if (active) {
      _schedulePoll();
    } else {
      _poll?.cancel();
      stop();
      _showPeer(false);
    }
  }

  void edited(bool hasText) {
    if (!_active || _unsupported || !isCurrent()) return;
    if (!hasText) {
      stop();
      return;
    }
    _localTyping = true;
    _idle?.cancel();
    _idle = Timer(_idleInterval, stop);
    if (_pulse?.isActive != true) _announceTyping();
  }

  void _announceTyping() {
    if (!_active || !_localTyping || _unsupported || !isCurrent()) return;
    _advertised = true;
    _write(true);
    // Keep the start cooldown even after a clear or send. A fresh edit can
    // resume as soon as the cooldown ends without rapid start/stop bursts.
    _pulse = Timer(_pulseInterval, () {
      if (!_advertised) _announceTyping();
    });
  }

  void stop() {
    _idle?.cancel();
    _localTyping = false;
    if (_advertised) {
      _advertised = false;
      _write(false);
    }
  }

  void dispose() {
    setActive(false);
    _pulse?.cancel();
    _peerExpires?.cancel();
  }

  void _write(bool typing) {
    final generation = _generation;
    // An outstanding "started" request must settle before we clear it.
    _writes = _writes.then((_) async {
      if (_unsupported || !isCurrent()) return;
      if (typing && (!_active || !_localTyping || generation != _generation)) {
        return;
      }
      try {
        await setTyping(typing);
      } on DioException catch (error) {
        if (error.response?.statusCode == 404) _unsupported = true;
      } catch (_) {
        // Presence is ephemeral. It never blocks drafts or message delivery.
      }
    });
  }

  void _schedulePoll() {
    if (!_active || _unsupported || !isCurrent()) return;
    final generation = _generation;
    _poll = Timer(_pollInterval, () async {
      try {
        final peer = await readPeer();
        if (_active && generation == _generation && isCurrent()) {
          _showPeer(peer);
        }
      } on DioException catch (error) {
        if (error.response?.statusCode == 404) _unsupported = true;
      } catch (_) {
        // Keep chat usable during network or presence service interruptions.
      } finally {
        if (generation == _generation) _schedulePoll();
      }
    });
  }

  void _showPeer(bool typing) {
    _peerExpires?.cancel();
    if (typing) _peerExpires = Timer(_peerExpiry, () => _showPeer(false));
    if (_peerTyping == typing) return;
    _peerTyping = typing;
    onPeerChanged(typing);
  }
}
