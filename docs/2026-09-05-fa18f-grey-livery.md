# Grey F/A-18F replacement: incomplete supplied texture

The supplied /sdcard/Download/FA18F_RAAF_Grey_GearUp.glb has identical mesh,
accessor, node, material and scene definitions to the working Gunmetal model.
Only image buffer view 4 changed; all other buffer views are byte-for-byte
identical. The downloaded source has been preserved untouched.

However, that replacement PNG is truncated at 5,637,157 bytes. Its last IDAT
chunk extends beyond the buffer view and it has no IEND. Concatenating IDAT
payloads and decompressing with zlib yields 64,098,577 bytes (3,912 complete
rows), short of the 67,112,960 bytes needed for its 4096x4096 RGBA image. The
zlib stream never reaches EOF. Godot reports ERR_FILE_CORRUPT and cannot load
image index 0. This is missing pixel data, not merely missing PNG metadata.

The replacement was therefore not shipped. The Super Hornet still uses the
working Gunmetal model, and the attempted import's files were moved to
/tmp/openstrike-grey-incomplete. The user was asked for a complete re-export.
After receiving it, validate PNG integrity before importing and retain the
2048-pixel limit on all three textures. The existing scale, orientation,
weapons, gear and twin afterburner positions apply if geometry stays identical.
