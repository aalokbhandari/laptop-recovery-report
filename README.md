# My laptop kept crashing, my screen kept going dark, and my iPhone photos broke. Here's what was actually wrong.

by Aalok Bhandari · October 2026

I have an ASUS TUF Gaming A15 (FA507RF) on Windows 11. For weeks it had a bunch of problems that I assumed were unrelated:

- it would just turn off or restart out of nowhere
- the screen kept getting darker and lighter by itself, with weird harsh contrast
- it felt slow and the disk kept filling up
- a lot of the iPhone photos and videos I'd copied to it wouldn't open anymore

So I sat down and went through the whole machine properly: event logs, driver settings, power plans, and every single photo file byte by byte. Turns out it was five different problems. This is what I found, how I proved it, and what I did about each one. All the scripts I used are in [`scripts/`](scripts) if you want to run the same checks on your own laptop.

---

## 1. The random shutdowns were the RAM

First stop was the Windows System log. In 30 days:

- **53 times** the laptop lost power without a proper shutdown (Kernel-Power event 41, 6 of them while going to sleep)
- **5 blue screens**: `0x0A`, `0x10E` (video memory) and `0x20001` (hypervisor) three times
- **2,307 "corrected hardware error" events, all saying `Component: Memory`**

That last one is the giveaway. A healthy RAM stick logs zero of these. Mine was logging about 75 a day. The blue screen codes I was getting are the classic "memory had a value it shouldn't" crashes too.

The laptop only has one 8 GB stick (the second slot is empty), and it was running at 0.7 GB free most of the time, so that stick was being hammered constantly.

I ran DISM and SFC to rule out broken Windows files. Both came back clean. So it's hardware. The fix is a new RAM kit, ideally 2 × 8 GB or 2 × 16 GB DDR5-4800, which also gives the AMD graphics dual-channel memory and a big speed boost. A BIOS update through MyASUS is worth doing too. Mine is from 2023 and newer ones exist for this model family.

## 2. The screen going dark was AMD trying to "help"

I checked the obvious stuff first. Theme was fixed on dark mode, Windows adaptive brightness was off, Night light was off. None of that.

Then I noticed something: **the screen went dark whenever a big black window was open** (my terminal), and went back to normal the moment I minimised it. That's content-adaptive brightness. AMD calls it **Vari-Bright**, and it was switched on in the driver at level 3. It looks at what's on screen, and if it's mostly dark, it dims the backlight and cranks the contrast. Exactly what I was seeing.

Fix: set `PP_VariBrightFeatureEnable = 0` in the AMD driver's registry key and restart. (Or turn off Vari-Bright in AMD Software → Display.)

But there was a second thing going on. Armoury Crate switches the Windows power plan when you plug in or unplug the charger, and each plan had its own display settings:

| Power plan | Screen brightness | Dims after idle | Colour mode on battery |
|---|---|---|---|
| Turbo | 100 % | yes, to 50 % | power saving |
| Performance | 75 % | yes | power saving |
| Silent | **29 %** | no | power saving |

So unplugging the charger could drop my screen from 100 % to 29 % and switch the colour rendering at the same time. No wonder it felt random. I set all three plans to the same thing: 100 % brightness, no idle dimming, colour on "visual quality" both plugged in and on battery. The script for checking this is `scripts/02-display.ps1`.

## 3. The slowness and the full disk

Nothing fancy here, just years of junk:

- npm cache: 10.2 GB
- temp files: 5.3 GB
- graphics shader caches, pip cache, crash dumps: about 1.7 GB

Clearing those freed **15.7 GB**. I also ran TRIM on the SSD, turned on Storage Sense so Windows cleans temp files weekly, and stopped five heavy apps (game launchers and a live wallpaper) from starting with Windows. With only 8 GB of RAM, every app that auto-starts is memory you don't get to use.

## 4. The photos: they didn't "go bad", they were broken from day one

This is the one that actually bugged me. My iPhone was full, so I plugged it into the laptop with a USB-C cable and copied everything over: 3,678 photos and videos. I checked a few, they looked fine, and I cleared space on the phone. Months later, loads of them wouldn't open.

My first thought was that they'd got corrupted over time. They hadn't. Here's how I know.

### Problem A: 411 files had the wrong extension

Every file format starts with a signature. A JPEG starts with `FF D8`. HEIC photos and MOV videos both have `ftyp` at byte 4, followed by `heic` or `qt`. So I read the first few bytes of every file and compared it with the extension:

```
ABEME9486.JPG   00 00 00 24 66 74 79 70 68 65 69 63   "ftypheic" -> actually a HEIC photo
ATXQ9752.HEIC   FF D8 FF E0 00 10 4A 46 49 46         JPEG       -> actually a JPEG
AUNY5560.MOV    FF D8 FF E0 00 10 4A 46 49 46         JPEG       -> actually a JPEG
```

Windows decides which app opens a file based on the extension, so a photo called `.MOV` gets sent to the video player and "fails". The file itself is totally fine. It just has the wrong name.

| Named as | Actually is | How many |
|---|---|---|
| .MOV | JPEG photo | 100 |
| .JPG | video | 94 |
| .HEIC | video | 48 |
| .MOV | HEIC photo | 48 |
| .JPG | HEIC photo | 36 |
| .HEIC | JPEG photo | 33 |
| other mixes | | 52 |

Those 33 `.HEIC` files that are really JPEGs are a big clue. That's exactly what you get when the iPhone converts a photo to JPEG during the transfer but Windows keeps the original name. The iPhone does this conversion when **Settings → Photos → Transfer to Mac or PC** is set to **Automatic**, which is the default.

Fixing these was easy: give each file the extension that matches what's actually inside.

### Problem B: 310 files were cut short

| Type | Cut short | Fine |
|---|---|---|
| MOV video | 236 | 327 |
| HEIC photo | 70 | 379 |
| MP4 video | 4 | 23 |

`ffprobe` says it straight out: `moov atom not found` for the videos and `partial file` for the photos. A video file is basically a big block of frames followed by an index (the `moov` box) telling the player where each frame is. In these files the copy stopped before the index, so the frames are there but no player can find them.

**Why I'm sure this happened during the copy and not afterwards:**

- All 3,678 files were written in one 32-minute session on the night of the import, and none of them were modified after.
- Disks that degrade flip random bits. They don't rename files, and they don't make a file shorter than its own index says it should be.
- OneDrive just uploads whatever bytes it's given.
- My dodgy RAM can flip bits during a copy, but it can't change a file's length or extension either.

What's left is the transfer itself: the iPhone converting files on the fly and Windows writing them with the wrong name or the wrong size, maybe plus the USB connection dropping at some point.

### Why they looked fine when I checked

An iPhone HEIC photo isn't one picture. It's 48 tiles of 512 × 512 pixels stitched into the 4032 × 3024 photo, **plus a separate small 320 × 240 thumbnail**. File Explorer and the Photos app show you that thumbnail. So a photo can show a perfect preview while the actual photo is broken. Scrolling through previews, I had no way of noticing.

I proved this by pulling a perfect thumbnail out of a photo that Windows refuses to open.

## 5. Getting the photos back

**Wrong extensions (411 files):** all fixed. Rename to the right extension and they open normally.

**Cut-short HEIC photos (70 files): mostly recovered.** This was the fun part. Windows rejects a HEIC completely if *any* part is damaged. But each tile is its own little image and can be decoded on its own. So I wrote `scripts/06-recover-heic-tiles.ps1`, which pulls out every tile that survived, stitches them back together, crops and rotates the result, and saves it as a JPG.

| Result | Photos |
|---|---|
| Fully rebuilt, nothing missing | 6 |
| 90–99 % of the photo back | 21 |
| 50–89 % back | 34 |
| Less than half back | 8 |
| Couldn't be rebuilt this way | 1 |

The typical photo came back with 81 % of it intact. The missing bit is always at the bottom, because that's where the file got cut off.

**Cut-short videos (240 files): not yet.** The frames are there, but the index is gone. A tool called [untrunc](https://github.com/anthwlock/untrunc) can rebuild the index using a healthy video from the same phone as a reference:

```
untrunc.exe -s healthy.mov broken.mov
```

That's my next step.

**The real fix** for anything that matters: the originals, if they're still on the phone or in iCloud Photos.

## Try it on your own files

You need PowerShell, and [FFmpeg](https://ffmpeg.org/) for videos and HEIC (`winget install Gyan.FFmpeg`). The checks only read your files, they never change them.

Check what a file *really* is:
```powershell
Format-Hex -Path .\IMG_1234.HEIC -Count 16
```

Scan a whole folder for wrong extensions and broken files:
```powershell
.\scripts\04-photo-signatures.ps1 -Folder "$env:USERPROFILE\Pictures\iphone"
```

Check a single video (a broken one says `moov atom not found`):
```powershell
ffprobe -v error -show_entries format=duration -of csv=p=0 .\clip.mov
```

Rebuild a broken HEIC from its tiles:
```powershell
.\scripts\06-recover-heic-tiles.ps1 -Files .\photo.heic -OutDir .\recovered
```

Make sure a copy is identical to the original (same hash = same file):
```powershell
Get-FileHash .\original.heic, .\copy.heic -Algorithm SHA256
```

The other scripts check for crashes and memory errors (`01`), display settings (`02`), disk usage (`03`) and rename photos into date order (`05`).

## What I'd tell anyone copying photos off an iPhone

1. Set **Settings → Photos → Transfer to Mac or PC → Keep Originals** before you plug in.
2. Copy in batches of a few hundred, not thousands at once, and keep the phone unlocked.
3. Compare the number of items on the phone with the number of files on the laptop.
4. Run a scan like the one above. **A preview is not a check.**
5. Only delete from the phone once everything checks out, and keep a second copy somewhere else for a while.
6. Install HEIF Image Extensions and HEVC Video Extensions from the Microsoft Store so Windows can open iPhone formats.

## What I want to build next

This is a really common situation for students. Phone storage runs out, iCloud costs money, and a Windows laptop with a cable is the free option. But nothing in that chain tells you when something goes wrong. The phone converts silently, Windows copies without checking, and the preview hides the damage until the originals are gone.

I couldn't find a free, simple tool that sits between "copy finished" and "safe to delete from your phone". So that's what I want to make. Point it at your import folder and it tells you what arrived intact, fixes wrong extensions in one click, rescues damaged photos from their tiles, and gives you a clear yes or no on clearing your phone.

## License

The scripts are [MIT](LICENSE) and the write-up is [CC BY 4.0](LICENSE-docs.md). © 2026 Aalok Bhandari.
