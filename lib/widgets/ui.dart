/// Building blocks shared by every screen (same look as the home tab).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';

Future<T?> push<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

Future<T?> replace<T>(BuildContext context, Widget screen) => Navigator.of(
  context,
).pushReplacement<T, Object?>(MaterialPageRoute(builder: (_) => screen));

const savedOfflineMessage =
    'مفيش اتصال: اتحفظ على الموبايل وهيتبعت أول ما النت يرجع.';

void toast(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

/// Copies [link] (e.g. رابط المديونية) to the clipboard and confirms with a toast.
Future<void> copyLink(BuildContext context, Future<String> link) async {
  try {
    await Clipboard.setData(ClipboardData(text: await link));
    if (context.mounted) toast(context, 'تم نسخ الرابط');
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}

/// tel: / maps links.
Future<void> openUrl(BuildContext context, String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) &&
      context.mounted) {
    toast(context, 'تعذر فتح الرابط.');
  }
}

/// Vertical list with page padding and even gaps; always scrollable (pull-to-refresh).
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.bottomPadding = 32});

  final List<Widget> children;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => children[i],
    );
  }
}

enum Tone { success, warning, danger, info, neutral }

extension ToneColors on Tone {
  (Color bg, Color fg) colors(BuildContext context) {
    final c = context.colors;
    return switch (this) {
      Tone.success => (c.successBg, c.successFg),
      Tone.warning => (c.warningBg, c.warningFg),
      Tone.danger => (c.dangerBg, c.dangerFg),
      Tone.info => (c.infoBg, c.infoFg),
      Tone.neutral => (c.neutralBg, c.neutralFg),
    };
  }
}

/// Same colors as the web status classes.
const statusTones = {
  'PENDING': Tone.warning,
  'PLANNED': Tone.warning,
  'APPROVED': Tone.success,
  'COMPLETED': Tone.success,
  'REJECTED': Tone.danger,
  'CANCELLED': Tone.danger,
  'IN_PROGRESS': Tone.info,
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Colored message box (notes, warnings, errors).
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.tone = Tone.warning});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(context);
    return Semantics(
      liveRegion: tone == Tone.danger,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(color: fg, fontSize: 13.5)),
      ),
    );
  }
}

/// Card with a title bar and rows separated by dividers.
/// [collapsible]: an accordion, closed until the title is tapped.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.empty = '',
    this.trailing,
    this.titleColor,
    this.collapsible = false,
  });

  final String title;
  final List<Widget> children;
  final String empty;
  final Widget? trailing;
  final Color? titleColor;
  final bool collapsible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleText = Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: titleColor,
      ),
    );
    final body = [
      Divider(height: 1, color: c.border),
      if (children.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        )
      else
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.border),
          children[i],
        ],
    ];
    if (collapsible) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: titleText,
          // Chevron on the start side so [trailing] (e.g. "عرض الكل") keeps the end.
          controlAffinity: ListTileControlAffinity.leading,
          trailing: trailing,
          tilePadding: const EdgeInsetsDirectional.only(start: 8, end: 12),
          shape: const Border(),
          collapsedShape: const Border(),
          childrenPadding: EdgeInsets.zero,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              trailing == null ? 14 : 6,
              12,
              trailing == null ? 10 : 2,
            ),
            child: Row(
              children: [
                Expanded(child: titleText),
                ?trailing,
              ],
            ),
          ),
          ...body,
        ],
      ),
    );
  }
}

/// One list row: title + subtitle, optional badge and amount on the end side.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingHint,
    this.trailingColor,
    this.trailingHintColor,
    this.badge,
    this.onTap,
    this.dimmed = false,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final String? trailingHint;
  final Color? trailingColor;
  final Color? trailingHintColor;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool dimmed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                  ],
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trailing!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: trailingColor,
                      ),
                    ),
                    if (trailingHint != null)
                      Text(
                        trailingHint!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: trailingHintColor ?? c.muted,
                        ),
                      ),
                  ],
                ),
              ],
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, size: 20, color: c.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two columns of cards on phones, four on wide screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.valueColor,
    this.hintColor,
  });

  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;
  final Color? hintColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: hintColor ?? c.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dark card for the money that matters most (treasury / a rep's cash box).
class HighlightCard extends StatelessWidget {
  const HighlightCard({
    super.key,
    required this.label,
    required this.value,
    this.lines = const [],
  });

  final String label;
  final String value;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dim = c.onHighlight.withValues(alpha: 0.75);
    return Card(
      color: c.highlight,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: dim)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: c.onHighlight,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (lines.isNotEmpty) ...[
              Divider(color: c.onHighlight.withValues(alpha: 0.2), height: 20),
              for (final l in lines)
                Text(l, style: TextStyle(color: dim, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Label / value pairs in a card (details pages).
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.items, this.footer});

  final List<(String, String)> items;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (label, value) in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        label,
                        style: TextStyle(color: c.muted, fontSize: 13.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      ),
    );
  }
}

/// Screen title with a status badge and wrapped action buttons under it.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.trailing,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? badge;

  /// Rendered opposite the title, on the same row (e.g. a single destructive action).
  final Widget? trailing;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  ?badge,
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(color: context.colors.muted)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

/// First-load placeholder: pulsing cards shaped like the list that is coming (still when animations are off).
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key});

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.border.withValues(alpha: 0.7);
    final list = ListView(
      // Sized to its items so it also works nested in a page list (e.g. a section's AsyncView).
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            height: 76,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
      ],
    );
    return Semantics(
      label: 'جاري التحميل',
      child: MediaQuery.disableAnimationsOf(context)
          ? list
          : FadeTransition(opacity: _pulse, child: list),
    );
  }
}

/// Empty list message inside a card.
class EmptyCard extends StatelessWidget {
  const EmptyCard(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.muted),
        ),
      ),
    );
  }
}

/// Horizontal filter chips (single choice). `null` value = "all".
class ChoiceBar<T> extends StatelessWidget {
  const ChoiceBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.leading,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Scrolls with the chips, before them (e.g. a [PeriodChip]).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: leading,
            ),
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: e.key == value,
                onSelected: (_) => onChanged(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

extension Dotted on Iterable<String> {
  /// "a · b · c" with each part in a Unicode isolate, so Latin names, numbers and dates
  /// in one line keep their order in right-to-left text.
  String dotted() => map((p) => '\u2068$p\u2069').join(' · ');
}
