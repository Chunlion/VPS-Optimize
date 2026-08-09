# VPS-Optimize 首页设计 QA

## Evidence

- Source visual truth: `C:\Users\Cuty\.codex\generated_images\019fe29b-d831-7c10-98b6-244c91b0c264\exec-3c743eca-113a-4a54-8335-7bd305c20229.png`
- Final implementation: `C:\Users\Cuty\.codex\visualizations\2026\08\09\vps-optimize-design-qa\implementation-home-refined-final.png`
- Side-by-side comparison: `C:\Users\Cuty\.codex\visualizations\2026\08\09\vps-optimize-design-qa\comparison-home-refined-final.png`
- Additional evidence: `implementation-doc-refined-final.png`, `implementation-home-refined-dark.png`, `implementation-home-refined-mobile.png`, `comparison-theme-toggle-dpi-final.png`, and the focused `comparison-cta-centered-final.png` in the same directory.
- State: Chinese home route, light theme, 1488 × 1058 CSS viewport.
- Source pixels: 1487 × 1058. Implementation capture: 1473 × 1047. The implementation was normalized to the source size only for the side-by-side comparison.

## Findings

- No actionable P0, P1, or P2 visual differences remain.
- Typography uses self-hosted Noto Sans SC for Chinese and Inter for English and Russian. Weight, hierarchy, wrapping, and line height follow the selected design.
- Hero, workflow, and editorial sections begin at the same visual landmarks as the source: workflow at 563 px and editorial content at 727 px.
- The 443 routing visual includes the gateway, Web, Xray, TCP Peek, routing lines, state indicators, localized labels, and dedicated light/dark assets.
- Navigation, controls, cards, status colors, shadows, borders, and background gradients use one shared visual system across home and documentation pages.
- The appearance control uses a 44 × 44 px target and an 18 × 18 px vector icon. Its light and dark icons remain centered instead of inheriting the horizontal offset from VitePress's compact switch track.
- Both hero CTA labels and their icons use flex alignment. The measured text-center offset is under 0.5 px for each button.
- Homepage copy is adapted to verified project behavior instead of repeating unsupported marketing claims.
- Chinese, English, and Russian editions keep the same structure and meaning.

## Interaction and responsive checks

- Primary CTA resolves to `/quick-start` and retains a clean accessible name.
- Theme switching loads the dedicated dark routing asset.
- Theme switching preserves the appearance control's dimensions and centered icon in both states.
- Mobile layout at 390 × 844 has no horizontal overflow; the navigation menu opens and closes.
- Chinese, English, and Russian routes use their localized routing asset and correct document language.
- Quick-start documentation, sidebar, outline, code blocks, and content cards use the same typography and surface styling as the homepage.
- Browser console warnings/errors: none.

## Comparison history

1. Initial build was rejected because its system font, generic routing visual, sparse workflow, and documentation styling did not match the selected reference closely enough.
2. The refined build added self-hosted fonts, localized detailed routing assets, a five-step workflow, a status-focused editorial section, and shared documentation tokens.
3. Final desktop, dark, mobile, multilingual, documentation, and side-by-side checks found no remaining P0/P1/P2 issues.
4. The appearance control was rechecked as a focused region after its DPI correction. The inherited switch-track offset was removed, the target and icon were resized, and the center delta measured 0 px on both axes.
5. The hero CTA labels were 3.67 px above the button center under the inherited inline layout. Switching both buttons to inline flex reduced the measured offset to 0.33 px without changing their size or position.

## Implementation checklist

- [x] Match the selected desktop hierarchy, typography, and section rhythm.
- [x] Recreate the detailed routing and workflow presentation.
- [x] Apply the same visual language to documentation pages.
- [x] Preserve existing VitePress routes and navigation behavior.
- [x] Synchronize Chinese, English, and Russian homepage content.
- [x] Verify desktop, mobile, light, dark, navigation, CTA, and documentation states.

final result: passed
