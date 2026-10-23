import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../../messages/data/message_repository.dart';

class BrokerContactButton extends ConsumerStatefulWidget {
  const BrokerContactButton({required this.brokerId, super.key});
  final int brokerId;
  @override
  ConsumerState<BrokerContactButton> createState() => _BrokerContactButtonState();
}
class _BrokerContactButtonState extends ConsumerState<BrokerContactButton> {
  bool _busy = false;
  Future<void> _open() async {
    if (_busy) return;
    var actor=ref.read(authControllerProvider).asData?.value;
    if(actor==null){await context.push('/auth');if(!mounted)return;actor=ref.read(authControllerProvider).asData?.value;}
    if(actor==null)return;
    if(!actor.isActive){await context.push('/verify-phone');return;}
    setState(()=>_busy=true);
    try {
      final thread=await ref.read(messageRepositoryProvider).startForBroker(widget.brokerId);
      if(!mounted)return;
      ref.read(messageDataRevisionProvider.notifier).state++;
      await context.push('/messages/${thread.id}');
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyApiError(e))));}
    finally {if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context) {
    if(ref.watch(authControllerProvider).asData?.value?.id==widget.brokerId)return const SizedBox.shrink();
    return TextButton.icon(key:ValueKey('broker-chat-${widget.brokerId}'),onPressed:_busy?null:_open,
      icon:_busy?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.chat_bubble_outline,size:18),
      label:const Text('محادثة مباشرة'));
  }
}
