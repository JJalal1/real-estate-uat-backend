# W3B1 review note

Status: REVIEW IN PROGRESS

The initial W3B1 implementation is structurally sound and `flutter analyze` is green, but acceptance is blocked by two concrete issues found during ordinary-session review:

1. The new Phase 1 CI run failed one RTL/text-scaling widget assertion because the test expected `RichText.textDirection` to be explicitly set even though the rendered `Text` inherits RTL from `Directionality` and may legally keep its own `textDirection` null.
2. Several motion/opacity and semantic-color values drift from the accepted W3A specification. The implementation must use the accepted values rather than introducing alternate scaffolding defaults.

The ordinary ChatGPT session will correct these narrow foundation/test issues on the same Phase 1 branch, rerun CI, and only then accept W3B1. No W3B2/W3C/screen redesign is authorized by this note.