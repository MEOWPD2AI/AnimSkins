# AnimSkins

Animated, glowing weapon skins for your first-person weapons in **PAYDAY 2**.

Pick a skin for each weapon slot, tune how it glows, make the gun see-through, let it react to the heist, or turn your own `.dds` images into skins, all from an in-game menu.

> Current version: **5.5**

## What it does

- **Your own skins**: the `.dds` images in `custom_skins/` are the skin list (plus the **Ghost** skin used by see-through)
- **Separate skin for your primary and secondary weapon**
- **Glow controls**: brightness, bloom, a breathing pulse, and an optional scrolling pattern with a choice of direction
- **See-through weapon**: a ghost look where walls and the world show through the gun, with an optional solid colour (14 to choose from)
- **Reactive glow**: dim ember in stealth, brighter during assaults, heat that builds up as you fire, or a flash on every shot
- **World light**: a real light at the muzzle so the glow lights up the room
- **Muzzle effects**: heat and sparkle particle effects
- **Generator**: turn your own `.dds` images into skins, no external tools needed

Weapons that already have a vanilla weapon skin equipped are left alone, and VR is not supported.

## Requirements

- PAYDAY 2
- [SuperBLT](https://superblt.znix.xyz/)
- [BeardLib](https://modworkshop.net/mod/14924)

## Installation

1. Install SuperBLT and BeardLib first (see their own pages).
2. Download the latest release zip (or `AnimSkins.zip`) and extract it.
3. Put the folder into your game's `mods` folder and make sure it is named **`AnimSkins`** (rename it if the zip gave it another name):

   ```
   PAYDAY 2/
   └── mods/
       └── AnimSkins/
           ├── mod.txt
           ├── main.xml
           ├── assets/
           │   ├── textures/
           │   └── units/
           ├── custom_skins/
           ├── data/
           ├── loc/
           ├── lua/
           ├── textures/
           └── units/
   ```

   Check that the textures are at `mods/AnimSkins/assets/textures/original/`.
   If you see an extra `assets/assets/` folder, move `textures` up one level.
4. Start the game.

**Updating:** delete the old `mods/AnimSkins` folder first, then install the new one.
Your settings are kept in `saves/`, so you will not lose them.

## Quick start

1. Start the game and open **Options > Mod Options > AnimSkins**.
2. Open **Skin** and choose a **Primary skin** and a **Secondary skin**.
3. Load into a heist. The skin is already glowing and breathing, and the glow reacts to stealth and assaults.
4. Want to change the look? Try the tweaks below.

| I want... | Do this |
| --- | --- |
| A brighter or dimmer glow (also the see-through weapon) | **Skin > Brightness & Speed > Glow brightness** (built for 5; past about 10 the bright parts turn white) |
| A gentler or faster pulse | **Skin > Breathing glow**, then adjust Breath rate and Breath depth |
| The pattern to move across the gun | Turn on **Skin > Scroll pattern** (works with See-through too, in small steps) |
| A ghost gun you can see through | Turn on **Skin > See-through weapon** and pick the **Ghost** skin (restart once the first time) |
| The ghost gun in one solid colour | **Skin > See-through Color**, turn on **Use color** and pick a colour |
| A glow that follows the heist | Leave **Reactive** on and tune it there |
| The gun to heat up as I fire | **Reactive**: leave **Flash per shot** off, then choose a **Muzzle heat effect** in **Muzzle effects** |
| A flash on every shot | **Reactive > Flash per shot**, and pick a **Star muzzle flash** in **Muzzle effects** |
| The glow to light the room | **World Light > World light** |
| Everything back to normal | Use the **Reset ... to defaults** button on each page, or switch off **Mod enabled** |

## Menu guide

Everything lives under **Options > Mod Options > AnimSkins**.

| Menu | What it does |
| --- | --- |
| **Skin** | Primary and secondary skin, Mod enabled, Scroll pattern, Breathing glow, See-through weapon, Show in menus |
| **Skin > Brightness & Speed** | Glow brightness (also controls the see-through weapon), Scroll speed, Scroll direction, Bloom |
| **Skin > See-through Color** | Paint the see-through weapon one solid colour: white, red, orange, gold, yellow, lime, green, mint, cyan, sky blue, blue, purple, magenta or pink |
| **World Light** | A real light at the muzzle: intensity, range and colour (red, green, blue) |
| **Reactive** | Glow changes with stealth, assaults, heat and shooting |
| **Muzzle effects** | Heat effect and star flash particle effects at the muzzle |
| **Generator** | Build skins from your own `.dds` files |

Every page has its own **Reset to defaults** button, so you can experiment safely.

### Skin

- **Mod enabled** is the master switch. Off puts the normal vanilla materials back straight away.
- **Breathing glow** pulses the brightness. It is on by default. Breath rate, Breath depth and Breath offset only appear while it is on.
- **Scroll pattern** moves the pattern across the weapon. It is off by default. Scroll speed and Scroll direction (in Brightness & Speed) only appear while it is on.
- **See-through weapon** makes the whole gun see-through. See-through strength only appears while it is on. Its brightness also follows Glow brightness (see below). Optics and sight glass are left alone.
- **Show in menus** also shows your skin on the main menu character, the lobby, inventory and customise previews. Turn it off to skin only the weapon in your hands during a heist.

**Scroll pattern + See-through weapon:** they can be used together. The see-through shader cannot scroll a texture, so the pattern moves in small steps by swapping between 48 pre-shifted copies of the skin (`custom_<name>_il_f00 ... _f47` in `assets/textures/original/` for the bundled skins, `<name>_il_f00 ... _f47` in `assets/textures/imported/` for skins you make with the Generator). It only moves left/right (Scroll direction picks which way) and the Ghost skin does not move. **Fixed 48 fps scroll** (on by default, in Skin) plays the frames at exactly 48 per second, smooth and independent of Scroll speed, heat and your game FPS. Turn it off to follow Scroll speed and the reactive heat speed instead (in small steps). It is off while See-through Color is on.

### See-through weapon and colour

Turn on **See-through weapon** in the Skin menu. **See-through strength** controls how solid it looks: low is a faint outline, high is a bright hologram.

**Brightness:** the see-through weapon also follows **Skin > Brightness & Speed > Glow brightness**. Raise Glow brightness to make it brighter and lower it to fade it out. It scales together with See-through strength, so use the two together to dial it in. Breathing glow and Reactive glow change its brightness too. Turning Glow brightness to 0 (or switching off Mod enabled) hides it.

Scroll speed, Scroll direction and Bloom do not apply to the see-through weapon.

The first time after installing, restart the game once so the see-through configs are built.

To paint it one colour, open **Skin > See-through Color**, turn on **Use color** and pick a colour. The weapon then uses the built-in white texture, tinted to your colour, instead of the skin pattern. Turn **Use color** off to get the skin back. Use color is greyed out until See-through weapon is on, and the Color choice is greyed out until Use color is on.

### Reactive glow

With **Reactive glow** on, the glow follows what is happening in the heist. It all scales your Glow brightness.

- **Stealth ember**: how much of the glow is shown while the level is still in stealth (0.35 is a faint ember, 1.0 means stealth changes nothing)
- **Assault surge**: how much brighter the glow gets during an assault. The build-up before the assault gets part of the way there.
- **Heat**: the longer you fire, the hotter the gun gets, which makes it glow brighter and scroll faster. **Heat per shot**, **Cooling rate**, **Heat glow** and **Heat scroll speed** tune it.
- **Flash per shot**: instead of heat building up, each shot makes the glow spike and fade. Flash strength and Flash decay tune it. The heat settings are ignored while this is on.
- **Response speed**: how quickly the glow follows when the heist state changes.

### Muzzle effects

- **Muzzle heat effect**: a looping effect at the muzzle while the gun is hot (Off, Overheat, Hailstorm heat, Sparks, Electric sparks or Drill sparks). **Effects start at** sets how hot the gun must be, and **Heat effect replay** sets how often it replays.
- **Star muzzle flash**: a sparkle fired from the muzzle on every shot (Kawaii sparkles, Sparkle burst, Small sparkles, Sniper glint, or one of the game's own muzzle flashes). **Star flash length** sets how long each one lives.

Some sparkle effects are only loaded in certain heists. If one does not show, try one of the entries marked (FPS), which always load.

## Make your own skin

1. Put a `.dds` image in `AnimSkins/custom_skins/` (or `saves/animskins_custom/`, which survives updates).
   - `myskin.dds`: the image is used as the skin
   - `myskin.dds` + `myskin_gradient.dds`: `myskin.dds` is a pattern coloured by the gradient (`_grad` also works)
2. In game: **Options > Mod Options > AnimSkins > Generator**
3. Pick a **Resolution** (1024 is the default, 2048 uses more memory and takes longer)
4. Tick `custom_myskin`, then press **Generate selected skins**
5. Restart the game (the game offers to restart for you)
6. Pick it in **Skin** (it is listed as `Imported: custom_myskin`)

Every generated skin also gets **48 see-through scroll frames** (`_f00` to `_f47`, 256x256 each, about 1.5 MB per skin), so **Scroll pattern** works with **See-through weapon** for your own skins too, exactly like the bundled ones. Generating takes a few seconds longer because of them. Skins you generated with an older version are listed as outdated: tick them and generate again to add the frames (until then they just do not move while see-through).

**Clear selection** unticks everything in the generator list. It does not delete any generated files.

How custom skins work: the image is used as the glow layer at full brightness on top of the built-in black texture. One main texture file is generated per skin, plus the 48 small scroll frames for the see-through weapon. The brightness is handled in game, not baked in.

Supported `.dds`: DXT1, DXT3, DXT5, uncompressed RGB/RGBA, luminance and their DX10 variants.
**BC7 / BC6 / BC5 are not supported**: re-save as DXT5 or uncompressed.
Square images (512 / 1024) tile best, and other sizes are resampled.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Gun is blank gray | Textures are in the wrong folder. Make sure they are in `assets/textures/original/` (not `assets/assets/...`). The BLT log shows `File does not exist! ... assets/textures/original/...` when this is the case |
| Gun is white or black | The skin's textures are missing. Re-generate the skin and restart |
| New custom skin does not appear | Generate it, then **restart the game** |
| See-through does nothing | Restart the game once after installing or updating so the see-through configs are built |
| Mod does nothing | Check that SuperBLT and BeardLib are installed and enabled, and that **Mod enabled** is on in the Skin menu |
| Menu items missing | Some options are hidden until their switch is on (for example turn on World light to see its sliders). Also make sure the old folder was deleted before updating |
| A weapon is not skinned | Weapons with a vanilla weapon skin equipped are skipped on purpose |

When asking for help, attach your BLT log (`mods/logs/`).

## Credits

- Made by Siuna, built on Inversion Universal
- Maintained by MeowAI
- Requires [BeardLib](https://modworkshop.net/mod/14924) and SuperBLT

## License

MIT
