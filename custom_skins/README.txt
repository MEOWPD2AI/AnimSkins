AnimSkins - your own skins from .dds files
==========================================

Drop .dds files in this folder (or in  saves/animskins_custom/ , which survives mod updates).

  myskin.dds                 -> the image is used as the skin as it is
  myskin.dds
  myskin_gradient.dds        -> color skin: myskin.dds is the pattern, myskin_gradient.dds colors it
                                (_grad also works as the suffix)

How it is used: the image goes in as the glow layer at full brightness on top of the built-in black
texture (one generated file per skin, nothing pre-darkened). The glow level is set at runtime.

Then in game:  Options > Mod Options > AnimSkins > Generator
  1. tick  "custom_myskin"
  2. press "Generate selected skins"
  3. restart the game
  4. pick the skin under AnimSkins > Skin  (it is listed as "Imported: custom_myskin")

Each generated skin also gets 48 small see-through scroll frames (_il_f00 ... _il_f47), so
Scroll pattern works together with See-through weapon for your own skins.

Supported .dds formats: DXT1, DXT3, DXT5, uncompressed RGB / RGBA, luminance,
and the DX10 variants of those. BC7 / BC6 / BC5 are not supported: re-save as DXT5 or uncompressed.
Textures should be square (512 / 1024) for the cleanest tiling; other sizes are resampled.
