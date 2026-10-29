// Transplanted from eBroker 1.8.0; see docs/WAVE3_HOME_SOURCE_MAP.json.
import 'package:flutter/material.dart';
import 'source_adapters.dart';
import 'responsive_size.dart';

class EbrokerHomeCategoryCard extends StatelessWidget {
  const EbrokerHomeCategoryCard({
    required this.frontSpacing,
    required this.onTapCategory,
    required this.category,
    super.key,
  });

  final bool? frontSpacing;
  final dynamic Function(SourceCategory category) onTapCategory;
  final SourceCategory category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: frontSpacing ?? false ? 5.0 : 0,
      ),
      child: GestureDetector(
        onTap: () {
          onTapCategory.call(category);
        },
        child: Row(
          children: <Widget>[
            Container(
              constraints: BoxConstraints(
                minWidth: 100.rw(context),
                minHeight: 48.rh(context),
              ),
              padding: EdgeInsets.only(
                left: 8.rw(context),
                right: 8.rw(context),
                top: 4.rh(context),
                bottom: 4.rh(context),
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: category.selected ? context.sourceColors.tertiaryColor : context.sourceColors.secondaryColor,
                border: Border.all(color: context.sourceColors.borderColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SourceImage(
                    imageUrl: category.image ?? '',
                    color: category.selected ? Colors.white : context.sourceColors.tertiaryColor,
                    width: 18.rw(context),
                    height: 18.rh(context),
                  ),
                  SizedBox(width: 12.rw(context)),
                  SizedBox(
                    child: SourceText(
                      category.translatedName ?? category.category ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      fontWeight: FontWeight.w400,
                      fontSize: context.sourceFonts.sm,
                      color: category.selected ? Colors.white : context.sourceColors.textColorDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
