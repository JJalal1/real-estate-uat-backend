#!/usr/bin/env python3
"""Reproduce the Wave3 UI transplant from the checksum-verified eBroker tree.

Only presentation bodies are carried across. Account, media, navigation and
financial behavior always comes from Aqer. No template backend is executed.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'mobile_app/lib/core/widgets/ebroker_home'
REFERENCE = '425f019070db73253ff77181c77623d28225cc25'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    records = []

    def source(path):
        data = (args.reference_root / path).read_bytes()
        records.append({'source': path, 'source_sha256': hashlib.sha256(data).hexdigest()})
        return data.decode()

    def emit(name, text, adaptations):
        text = '// Transplanted from eBroker 1.8.0; see docs/WAVE3_HOME_SOURCE_MAP.json.\n' + text
        records[-1].update(target='mobile_app/lib/core/widgets/ebroker_home/' + name,
                           target_sha256=hashlib.sha256(text.encode()).hexdigest(), adaptations=adaptations)
        dest = TARGET / name
        if args.check:
            if dest.read_text() != text:
                raise SystemExit('Transplant differs: ' + name)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(text)

    def common(text):
        # Dart 3.10 shorthand is incompatible with the retained Dart 3.6 SDK.
        text = re.sub(r'(?<=[: ])\.start\b', 'CrossAxisAlignment.start', text)
        text = re.sub(r'(?<=[: ])\.min\b', 'MainAxisSize.min', text)
        text = text.replace('textAlign: .center', 'textAlign: TextAlign.center')
        text = text.replace('CustomText(', 'SourceText(').replace('CustomImage(', 'SourceImage(')
        text = text.replace('context.color.', 'context.sourceColors.').replace('context.font.', 'context.sourceFonts.')
        text = re.sub(r'(?<=[: ])\.w([4-7])00\b', r'FontWeight.w\g<1>00', text)
        return text

    def replace_call(text, marker, replacement):
        start = text.index(marker)
        opening = text.index('(', start)
        depth, quote, escaped = 0, None, False
        for end in range(opening, len(text)):
            char = text[end]
            if quote:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == quote:
                    quote = None
                continue
            if char in ('"', "'"):
                quote = char
            elif char == '(':
                depth += 1
            elif char == ')':
                depth -= 1
                if depth == 0:
                    return text[:start] + replacement + text[end + 1:]
        raise ValueError('Unbalanced original call: ' + marker)

    text = source('app/lib/utils/responsive_size.dart')
    emit('responsive_size.dart', text, ['Unchanged original responsive sizing; no dependency additions.'])

    text = source('app/lib/ui/screens/widgets/project_image_swiper.dart')
    text = text.replace("import 'package:ebroker/exports/main_export.dart';\nimport 'package:material_ui/material_ui.dart';",
                        "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';\nimport 'source_adapters.dart';\nimport 'responsive_size.dart';")
    text = common(text)
    text = text.replace('class ProjectImageSwiper', 'class EbrokerHomeImageSwiper').replace('const ProjectImageSwiper', 'const EbrokerHomeImageSwiper')
    text = text.replace('State<ProjectImageSwiper>', 'State<EbrokerHomeImageSwiper>')
    text = text.replace('  @override\n  void dispose()', '''  @override
  void didUpdateWidget(covariant EbrokerHomeImageSwiper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.images, widget.images)) {
      _currentIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(widget.images.length > 1
            ? _kInitialPageMultiplier * widget.images.length : 0);
        }
      });
    }
  }

  @override
  void dispose()''')
    text = text.replace('              PageView.builder(\n', "              PageView.builder(\n                key: PageStorageKey('source-gallery-${widget.heroTag}'),\n                allowImplicitScrolling: false,\n")
    text = text.replace('duration: _kWindowDuration,', 'duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : _kWindowDuration,')
    emit('image_swiper.dart', text, ['Original looping PageView and complete animated ScrollingDotsIndicator.',
        'CustomImage delegates to the existing viewport-aware sanitized media/cache path.',
        'Fence changed image collections, disable implicit offscreen loading, preserve route/page state and reduced motion.'])

    text = source('app/lib/ui/screens/home/widgets/category_card.dart')
    text = text[text.index('class CategoryCard'):]
    text = text.replace('CategoryCard', 'EbrokerHomeCategoryCard').replace('Category category', 'SourceCategory category')
    text = text.replace('final Category category;', 'final SourceCategory category;')
    text = common(text)
    text = text.replace('minHeight: 28.rh(context),', 'minHeight: 48.rh(context),')
    text = text.replace('color: context.sourceColors.secondaryColor,', 'color: category.selected ? context.sourceColors.tertiaryColor : context.sourceColors.secondaryColor,')
    text = text.replace('color: context.sourceColors.tertiaryColor,', 'color: category.selected ? Colors.white : context.sourceColors.tertiaryColor,')
    text = text.replace('fontSize: context.sourceFonts.sm,', 'fontSize: context.sourceFonts.sm,\n                      color: category.selected ? Colors.white : context.sourceColors.textColorDark,')
    text = "import 'package:flutter/material.dart';\nimport 'source_adapters.dart';\nimport 'responsive_size.dart';\n\n" + text
    emit('category_card.dart', text, ['Original rectangular category card, dimensions, icon/text spacing and callbacks.',
        'Canonical Aqer type taxonomy and selected state; minimum 48 logical-pixel touch target.'])

    original = source('app/lib/ui/screens/home/widgets/property_card_big.dart')
    body = original[original.index('    return GestureDetector('):original.index('                if (isFromCompare) ...[')]
    tail = original[original.index('            if ((showLikeButton'):original.index('  Widget _buildPrice(')]
    body += '''                if (widget.facts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final fact in widget.facts) Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(fact.icon, size: 13, color: context.sourceColors.textLightColor),
                      const SizedBox(width: 3), Flexible(child: SourceText(fact.label, fontSize: 10, maxLines: 1)),
                    ]),
                  ]),
                ],
                if (property.advanceLabel != null) SourceText(property.advanceLabel!, fontSize: 10),
                if (widget.action != null) widget.action!,
              ],
            ),
''' + tail
    body = body.replace('widget.isFromGrid ? 254.rw(context) : 290.rw(context)', 'double.infinity')
    body = body.replace('ProjectImageSwiper(', 'EbrokerHomeImageSwiper(')
    start = body.index('                    if (isPremium) ...[')
    stop = body.index('                  ],\n                ),', start)
    body = body[:start] + body[stop:]
    body = body.replace('            if ((showLikeButton ?? true) && !isAddedByMe)', '            if (widget.favorite != null)')
    body = body.replace('height: 34.rh(context),', 'height: 48,').replace('width: 34.rw(context),', 'width: 48,')
    body = replace_call(body, 'LikeButtonWidget(', 'widget.favorite')
    body = body.replace('SellRentLabel(', 'SourcePurposeLabel(')
    body = body.replace('child: PromotedCard(),', 'child: SourceSpotlightBadge(),')
    # Original location text lacks a flex constraint and overflows narrow Arabic cards.
    body = body.replace("                    CustomText(\n                        property.city ?? '',", "                    Flexible(child: CustomText(\n                        property.city ?? '',")
    body = body.replace('fontWeight: .w400,\n                      ),', 'fontWeight: .w400,\n                      )),')
    # Price and transaction remain source components; a Wrap is required for large Arabic text.
    body = body.replace('                Row(\n                  crossAxisAlignment: .start,\n                  children: [\n                    Expanded(\n                      child: _buildPrice(',
                        '                Wrap(\n                  spacing: 8, runSpacing: 6,\n                  crossAxisAlignment: WrapCrossAlignment.center,\n                  children: [\n                    _buildPrice(')
    body = body.replace('                        resolvedHeroTag,\n                      ),\n                    ),', '                        resolvedHeroTag,\n                      ),')
    body = body.replace('UiUtils.getDivider(context)', 'Divider(height: 1, color: context.sourceColors.borderColor)')
    body = common(body)
    header = '''import 'package:flutter/material.dart';
import 'app_components.dart' as unused;
'''
    header = '''import 'package:flutter/material.dart';
import '../app_components.dart';
import 'source_adapters.dart';
import 'responsive_size.dart';
import 'image_swiper.dart';

class EbrokerHomePropertyCard extends StatelessWidget {
  const EbrokerHomePropertyCard({required this.property, required this.onTap,
    this.isFromGrid = true, this.favorite, this.action, this.facts = const [], super.key});
  final SourceProperty property;
  final VoidCallback onTap;
  final bool isFromGrid;
  final Widget? favorite, action;
  final List<AppPropertyFact> facts;
  @override
  Widget build(BuildContext context) {
    final widget = this;
    final property = widget.property;
    final isRent = property.isRent;
    final isPromoted = property.isSpotlight;
    const showFeatured = false;
    final price = property.priceLabel;
    final resolvedHeroTag = 'home-property-${property.id}';
    final propertyImages = property.images;
    final handleCardTap = onTap;
'''
    footer = '''  Widget _buildPrice(BuildContext context, String price, bool isRent, String resolvedHeroTag) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SourceText(price, fontWeight: FontWeight.w500, fontSize: 12, color: context.sourceColors.tertiaryColor),
      if (isRent) SourceText(property.rentLabel, fontSize: context.sourceFonts.xxs,
        color: context.sourceColors.tertiaryColor),
    ]);
}
'''
    text = header + body + footer
    text = text.replace('(showFeatured ?? false)', 'showFeatured')
    emit('property_card_big.dart', text, ['Original PropertyCardBig presentation body and image/category/title/location/divider/price hierarchy.',
        'Original paid/premium/guest/comparison backend removed; real Aqer navigation, comparison, favorite and editorial Spotlight supplied.',
        'Actual Yemeni currency/monthly-vs-advance values, applicable compact facts, constrained long Arabic locations and accessible favorite target.',
        'Intrinsic responsive rows replace fixed 248px source grid where Arabic/font scaling would clip.'])

    original = source('app/lib/ui/screens/agent_mode/cards/agent_card.dart')
    body = original[original.index('    return GestureDetector(', original.index('  Widget build(BuildContext context)')):]
    start = body.index('      onLongPress:')
    stop = body.index('      onTap:', start)
    body = body[:start] + body[stop:]
    start = body.index('                  if (_showActions)')
    stop = body.index('                  Positioned(', start)
    body = body[:start] + body[stop:]
    body = body.replace('onTap: _openDetails,', 'onTap: onTap,')
    body = body.replace('widget.width ?? 285.rw(context)', 'width')
    body = replace_call(body, 'CustomImage(\n                          imageUrl: bannerUrl.isNotEmpty', '''DecoratedBox(decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [context.sourceColors.tertiaryColor.withValues(alpha: .13),
                            context.sourceColors.tertiaryColor.withValues(alpha: .03)])))''')
    body = body.replace('widget.agent.profile.isNotEmpty', "(profile.photoUrl?.isNotEmpty ?? false)")
    body = body.replace('widget.agent.profile', "profile.photoUrl ?? ''")
    body = body.replace('widget.agent.name.firstUpperCase()', 'profile.name')
    body = body.replace('widget.agent.email', 'profile.typeLabel')
    body = body.replace('widget.agent.isAgentVerified ||\n                            widget.agent.isAdmin', 'profile.verified')
    body = body.replace('widget.agent.id', 'profile.id')
    body = body.replace("'$formattedFollowers - ${'followers'.translate(context)}'", 'ratingLabel')
    body = body.replace('AppIcons.following', "'star'")
    body = body.replace('AppIcons.defaultPersonLogo', "'defaultProfileIcon'")
    body = body.replace("'${'properties'.translate(context)}: ${widget.agent.propertyCount}'", "'عقارات: ${profile.activeListings}'")
    body = body.replace("'${'projects'.translate(context)}: ${widget.agent.projectsCount}'", "'صفقات مؤكدة: ${profile.completedDeals}'")
    body = replace_call(body, 'VerifiedBadge.agentWithBackground(', '''Container(padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: context.sourceColors.secondaryColor, shape: BoxShape.circle),
                                child: Icon(Icons.verified, size: 13, color: context.sourceColors.tertiaryColor))''')
    start = body.index('            if (_showContactButtons) ...[')
    stop = body.index('            ],', start) + len('            ],')
    body = body[:start] + '''            const SizedBox(height: 8),
            TextButton(onPressed: onTap, child: const Text('عرض الملف والتواصل')),
''' + body[stop:]
    body = common(body)
    text = '''import 'package:flutter/material.dart';
import '../../../features/broker/domain/broker_models.dart';
import 'source_adapters.dart';
import 'responsive_size.dart';

class EbrokerHomeAgentCard extends StatelessWidget {
  const EbrokerHomeAgentCard({required this.profile, required this.onTap, this.width = 285, super.key});
  final BrokerProfile profile;
  final VoidCallback onTap;
  final double width;
  @override
  Widget build(BuildContext context) {
    final resolvedHeroTag = 'home-agent-${profile.id}';
    final largeText = MediaQuery.textScalerOf(context).scale(11.5) > 18;
    final ratingLabel = profile.ratingCount == 0 ? 'لا تقييمات بعد'
      : '${profile.rating.toStringAsFixed(1)} · ${profile.ratingCount} تقييم';
''' + body
    text = text.replace('                  Positioned(\n                    right: 4.rw(context),', '                  if (!largeText) Positioned(\n                    right: 4.rw(context),')
    text = text.replace('            // Property & Project counts', '            if (largeText) Padding(padding: const EdgeInsets.only(bottom: 8),\n              child: SourceText(ratingLabel, fontSize: 11.5, color: context.sourceColors.tertiaryColor)),\n            // Property & Project counts')
    # Source uses physical positioning; mirror the avatar/rating arrangement in Arabic.
    text = text.replace('Positioned(\n                    right: 4.rw(context),', 'PositionedDirectional(\n                    end: 4.rw(context),')
    text = text.replace('                  Positioned(\n                    left: 6.rw(context),', '                  PositionedDirectional(\n                    start: 6.rw(context),')
    emit('agent_card.dart', text, ['Original AgentCard presentation body/banner-avatar/name/stats composition.',
        'No source follow/appointments/WhatsApp/private email/project claims. Existing authorized public profile/contact route.',
        'Unavailable public cover is a neutral color gradient; no demo imagery. Actual verified state, ratings, listing and confirmed-deal counts.',
        'Directional positioning for RTL and intrinsic text/button height for accessibility.'])

    original = source('app/lib/ui/screens/widgets/like_button_widget.dart')
    animation = original[original.index('    _controller = AnimationController('):original.index('    WidgetsBinding.instance.addPostFrameCallback')]
    text = """import 'package:flutter/material.dart';
import '../ebroker_widgets.dart';

class EbrokerHomeFavoriteVisual extends StatefulWidget {
  const EbrokerHomeFavoriteVisual({required this.selected, required this.busy, this.onPressed, super.key});
  final bool selected, busy;
  final Future<void> Function()? onPressed;
  @override
  State<EbrokerHomeFavoriteVisual> createState() => _EbrokerHomeFavoriteVisualState();
}
class _EbrokerHomeFavoriteVisualState extends State<EbrokerHomeFavoriteVisual> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _activating = false;
  @override
  void initState() {
    super.initState();
""" + animation + """  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  Future<void> _activate() async {
    if (_activating || widget.onPressed == null) return;
    _activating = true;
    if (!MediaQuery.disableAnimationsOf(context)) _controller.forward(from: 0);
    try { await widget.onPressed!(); } finally { _activating = false; }
  }
  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: widget.selected,
    label: widget.selected ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPressed == null ? null : _activate,
      child: SizedBox.square(dimension: 48, child: Center(child: Container(
        width: 34, height: 34, alignment: Alignment.center,
        decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
        child: widget.busy ? const SizedBox.square(dimension: 15,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : ScaleTransition(scale: _scaleAnimation, child: EbrokerImage(
            widget.selected ? 'heart_filled' : 'heart', size: 24, color: Colors.white)),
      )))));
}
"""
    emit('favorite_visual.dart', text, ['Original 300ms cubic 1-1.4-1 scale animation and circular white-heart presentation.',
        'Existing Aqer authenticated favorite action and server/account truth; no template optimistic Cubit or agent-role bypass.',
        '48px accessible hit area, reduced motion and single activation through navigation/network waits.'])

    manifest = {'reference_commit': REFERENCE, 'archive_sha256': '4d57450d87d471be8758ec3f350e9867ed56f5d46b4b56bb4a8fb3f7c756a0cc',
                'source_files': records}
    path = ROOT / 'docs/WAVE3_HOME_SOURCE_MAP.json'
    serialized = json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if path.read_text() != serialized:
            raise SystemExit('Transplant manifest differs')
    else:
        path.write_text(serialized)
    print(json.dumps({'transplanted_components': len(records), 'verified': args.check}))


if __name__ == '__main__':
    main()
