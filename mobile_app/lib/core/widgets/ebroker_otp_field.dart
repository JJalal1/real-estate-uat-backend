import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ebroker_design.dart';

// auth/otp_screen.dart's UnderlineDecoration: six digits, 22px text,
// 1.5px underline and the source teal/grey listening colors. The existing
// controller and verification callback remain authoritative.
class EbrokerOtpField extends StatelessWidget {
  const EbrokerOtpField({required this.controller, this.onSubmitted, super.key});
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(height: 60.rh(context) + (MediaQuery.textScalerOf(context).scale(22) - 22) * 1.3,
      child: Stack(children: [
        Positioned.fill(child: ExcludeSemantics(child: IgnorePointer(
          child: ValueListenableBuilder<TextEditingValue>(valueListenable: controller,
            builder: (context, value, _) => Row(children: [
              for (var index = 0; index < 6; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: Container(alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 1.5,
                    color: index < value.text.length ? Theme.of(context).colorScheme.primary : Colors.grey))),
                  child: Text(index < value.text.length ? value.text[index] : '',
                    style: TextStyle(fontFamily: 'PrimaryFont', fontSize: 22.rf(context),
                      color: EbrokerDesign.text.withValues(alpha: .8))))),
              ],
            ]))))),
        Positioned.fill(child: Opacity(opacity: 0, alwaysIncludeSemantics: true,
          child: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode], maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done, onSubmitted: onSubmitted,
            decoration: const InputDecoration(labelText: 'رمز التحقق', counterText: '',
              border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none)))),
      ])),
  );
}
