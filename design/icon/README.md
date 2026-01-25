# TonePhone app icon source

Source files for the TonePhone app icon.

## Workflow

1. Edit icon in design tool (Sketch, Figma, Affinity Designer, or similar)
2. Export 1024×1024 PNG as master source
3. Generate size variants for macOS (16, 32, 64, 128, 256, 512, 1024)
4. Import into `apps/macOS/TonePhone/Assets.xcassets/AppIcon.appiconset/`

## Regenerating variants

When the source icon changes, regenerate all macOS PNG variants to keep committed assets in sync. You can use:
- Xcode's asset catalog (drag and drop PNG files)
- `iconutil` CLI to convert .iconset to .icns
- Design tool export presets for Apple icon sizes

## Files

- `TonePhone.icon/` - Icon Composer project (legacy)
- `Icon.png` - Current master source
- `macOs/` - macOS size variants
- `ios/` - iOS size variants

## Related

- [UI_GUIDELINES.md](../../UI_GUIDELINES.md) - Icon design rules and constraints
