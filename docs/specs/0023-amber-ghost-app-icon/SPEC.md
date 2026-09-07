---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0023"
  slug: amber-ghost-app-icon
  dir: 0023-amber-ghost-app-icon
references:
  - id: issue-77
    name: Give Hyperlite a Blade Runner 2049 amber ghost app icon
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/77
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: ghost silhouette, icns packaging, and menu-bar mark split
    status: active
skills: []
---

# Amber Ghost App Icon

## PURPOSE

Make the packaged Hyperlite app icon immediately distinct from Cursor in
Dock and Finder while keeping the ghost-emoji silhouette.

## CONTEXT

The 0002 liquid-chrome ghost is a premium engineered object, but its
graphite-and-titanium lighting is easy to confuse with Cursor's dark app
icon. The operator selected the Blade Runner 2049 Officer K dusk palette
(amber and burnt copper) from four generated options: Joi hologram cyan
and magenta, Officer K amber, Las Vegas pink and violet, and rain-city
teal and acid green.

The photorealistic Dock icon and the code-native monochrome menu-bar mark
intentionally share a silhouette, not a raster. This feature changes only
the packaged app-icon master.

Orchestration: single-lane, because this is one visual-identity asset, its
generation prompt, and the existing `iconutil` packaging path.

## REQUIREMENTS

- R1: Replace `macos/Hyperlite/Assets/HyperliteIcon.png` with the selected
  1024-pixel amber dusk ghost, preserving the rounded ghost silhouette,
  circular black-glass eyes, and short horizontal vent.
- R2: Keep the current transparent rounded-corner mask so macOS packaging
  continues to receive a 1024-square RGBA master.
- R3: Record the accepted generation and refinement prompts in
  `macos/Hyperlite/Assets/HyperliteIcon.prompt.md`.
- R4: Keep `scripts/build-macos-app.sh` producing `Hyperlite.icns` with 16
  through 1024 representations and `CFBundleIconFile` pointing at that file.

Non-goals:

- Changing the code-native monochrome menu-bar ghost.
- Adopting cyan/magenta, Vegas pink, or rain-city green.
- Adding text, franchise characters, or extra facial features.

Observable acceptance:

- The Dock/Finder icon is the amber dusk ghost, not liquid chrome.
- Packaged `Hyperlite.icns` still contains every required size.

## ACCEPTED PLAN

1. Generate four 2049 palette options from the current chrome master; the
   operator selects Officer K amber.
2. Composite that render onto the existing 1024 RGBA rounded-corner mask.
3. Update the icon prompt and this spec with the accepted palette and the
   rejected alternatives.
4. Rebuild the macOS app and inspect the bundled `.icns`.

## DECISIONS

- Use Officer K amber and burnt copper rather than cyan/magenta, Vegas
  pink, or rain-city green. The operator chose that option for Dock
  distinctiveness while keeping a metallic ghost, not a hologram sticker.
- Reuse the previous master's exact binary alpha (30,612 transparent corner
  pixels, otherwise opaque). Do not invent a new squircle.
- Leave the menu-bar mark as the code-native silhouette. It is already
  distinct from Cursor and must stay sharp at status-item sizes.

## DISCOVERIES

- The previous master is 1024 RGBA with a hard rounded-corner mask and an
  sRGB profile. Generated renders arrived as 1024 RGB with no alpha, so
  packaging required compositing rather than a raw replace.
- `sips` plus `iconutil` still derive every 16 through 1024 representation
  from that one master.

## VALIDATION

- Source inspection: 1024×1024, 4 samples, hasAlpha, sRGB IEC61966-2.1,
  identical transparent-pixel count to the previous master.
- `make macos-test` passed.
- `make macos-build` produced `build/Hyperlite.app`.
- `codesign --verify --deep --strict build/Hyperlite.app` passed.
- `CFBundleIconFile` is `Hyperlite.icns`; round-trip `iconutil` extraction
  contains 16, 32, 128, 256, 512, and 1024 representations.
- Go `fmt-check`, `vet`, `test`, and `test-race` are unchanged by this
  asset swap; GitHub Actions still runs them on the pull request.

## OUTCOME

The packaged app icon is the selected amber dusk ghost. The menu-bar ghost
mark is unchanged. Interactive Dock/Finder confirmation is operator
follow-up after installing or opening the rebuilt app.

## REPOSITORY MEMORY

- Decision: created
- Rationale: Palette choice, rejected alternatives, and the Dock-versus
  menu-bar split are product identity that the PNG bytes do not explain.
- Artifacts: `docs/specs/0023-amber-ghost-app-icon/SPEC.md`,
  `docs/specs/0002-command-palettes/SPEC.md`,
  `macos/Hyperlite/Assets/HyperliteIcon.prompt.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`
