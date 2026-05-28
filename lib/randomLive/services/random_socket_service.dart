import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/socket_service.dart';

class RandomSocketService {
  static final RandomSocketService _instance = RandomSocketService._internal();
  factory RandomSocketService() => _instance;
  RandomSocketService._internal();

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void init() {
    final socket = SocketService().socket;
    if (socket == null) return;

    debugPrint("[RandomSocket] Initializing listeners...");

    // CLEAR PREVIOUS TO AVOID DUPLICATES
    socket.off('random_room_created');
    socket.off('random_match_found');
    socket.off('random_partner_left');
    socket.off('random_searching_again');
    socket.off('random_offer');
    socket.off('random_answer');
    socket.off('random_candidate');
    socket.off('random_call_state_sync');
    socket.off('random_partner_blocked');
    socket.off('random_block'); // Added safety

    socket.on('random_room_created', (data) => _eventController.add({'event': 'random_room_created', 'data': data}));
    socket.on('random_match_found', (data) => _eventController.add({'event': 'random_match_found', 'data': data}));
    socket.on('random_partner_left', (data) => _eventController.add({'event': 'random_partner_left', 'data': data}));
    socket.on('random_searching_again', (data) => _eventController.add({'event': 'random_searching_again', 'data': data}));
    socket.on('random_offer', (data) => _eventController.add({'event': 'random_offer', 'data': data}));
    socket.on('random_answer', (data) => _eventController.add({'event': 'random_answer', 'data': data}));
    socket.on('random_candidate', (data) => _eventController.add({'event': 'random_candidate', 'data': data}));
    socket.on('random_call_state_sync', (data) => _eventController.add({'event': 'random_call_state_sync', 'data': data}));
    socket.on('random_partner_blocked', (data) => _eventController.add({'event': 'random_partner_blocked', 'data': data}));
  }

  void findPartner(String userId) {
    SocketService().emit('find_partner', {'userId': userId});
  }

  void leaveRoom(String userId) {
    SocketService().emit('leave_random_room', {'userId': userId});
  }

  void nextPartner(String userId) {
    SocketService().emit('next_partner', {'userId': userId});
  }

  void emitOffer(String roomId, String targetId, dynamic offer) {
    SocketService().emit('random_offer', {
      'roomId': roomId, 
      'targetId': targetId, 
      'offer': offer
    });
  }

  void emitAnswer(String roomId, String targetId, dynamic answer) {
    SocketService().emit('random_answer', {
      'roomId': roomId, 
      'targetId': targetId, 
      'answer': answer
    });
  }

  void emitCandidate(String roomId, String targetId, dynamic candidate) {
    SocketService().emit('random_candidate', {
      'roomId': roomId, 
      'targetId': targetId, 
      'candidate': candidate
    });
  }

  void syncCallState(String roomId, String targetId, bool isVideoOff) {
    SocketService().emit('random_call_state_sync', {
      'roomId': roomId,
      'targetId': targetId,
      'isVideoOff': isVideoOff
    });
  }

  void emitBlock(String roomId, String targetId) {
    SocketService().emit('random_block', {
      'roomId': roomId,
      'targetId': targetId
    });
  }

  void dispose() {
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('random_room_created');
      socket.off('random_match_found');
      socket.off('random_partner_left');
      socket.off('random_searching_again');
      socket.off('random_offer');
      socket.off('random_answer');
      socket.off('random_candidate');
      socket.off('random_call_state_sync');
      socket.off('random_partner_blocked');
    }
  }
}
