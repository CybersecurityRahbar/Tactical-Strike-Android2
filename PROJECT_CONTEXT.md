# Tactical Strike — Project Context

> This file is cumulative. Add confirmed requirements, design decisions, implementation status, test results, and known issues here after each meaningful project step. Do not record unrelated entertainment conversations or other projects here.

## Project identity and workflow

- Repository: https://github.com/CybersecurityRahbar/Tactical-Strike-Android
- Primary platform: Android.
- Engine: Godot 4.7.2 stable (do not switch to a beta engine version without a reason).
- Renderer: Compatibility renderer, initially targeting broad Android compatibility and modest hardware.
- All source, scene files, configuration, documentation, and CI build definitions live in this repository.
- The user does not want to use their own computer for development. Code changes and Android builds should happen in GitHub; GitHub Actions should validate and export APK artifacts. The user's Android phone is used to install and test APK builds.
- Work on the `main` branch, keeping the workflow straightforward and avoiding unnecessary branches.
- A GitHub APK artifact is a test build, not proof that gameplay is correct. Device testing remains necessary.

## High-level game concept

Create an original, small-scope but polished first-person tactical infantry game. It may be inspired by the broad genre of SFG2 / tactical shooters, but it must have its own name, map, interface, assets, code, and identity. The first release focuses on one large, carefully designed map rather than many small maps.

The intended experience is deliberate, long-range and positional rather than dominated by close-quarters run-and-gun combat.

## Battlefield — user's requirements

- One wide battlefield as the only initial map.
- Long sightlines. The opposing defensive position should be far away. Soldiers at long distance should naturally appear small or atmospheric silhouettes, and become more visually detailed as the player approaches.
- The terrain is a semi-level plateau with rolling, broken and irregular ground: alternating low and high ridges, rises, shallow dips and uneven approaches.
- Soil is dry, dusty brown plateau earth. It is **not** a sand-dune desert and **not** lush or green terrain.
- The attacker sector should include open approach ground and forward cover.
- The central approach should contain varied low and high ground that breaks lines of sight and creates tactical decisions.
- The defender sector should be distant and contain two separated houses/buildings, multiple trenches, sandbag positions, barriers, walls and firing positions.
- Defensive and attacker cover should include earth-filled sandbags, brick, stone and solid walls.
- Bullet impacts on the ground and cover should raise dust. Large-calibre impacts should create stronger, wider and more forceful dust effects than rifle-calibre impacts.

## Combat and AI — user's requirements

- Defenders generally hold prepared trenches and firing positions.
- Defenders should move between cover positions when their current position is under heavy fire.
- A defender may withdraw to a safer fallback position when pressure becomes too high.
- Attackers should advance slowly and cautiously, use suppressive fire, and avoid rushing into a strong defensive position.
- Attackers should try to weaken or suppress the defenders before committing to an assault.
- Attackers should advance after the defensive line becomes sufficiently weakened.
- Bot behavior should have readable tactical states such as hold, suppress, reposition, advance and retreat; it should not be random rushing.
- The human player remains free to move and choose their own approach.

## Weapons and game-ballistics — user's requirements

Initial weapon list:
- AK-74.
- M4A1.
- PKM (Russian general-purpose machine gun).
- RPG-7.
- SVD / Dragunov sniper rifle.
- DShK 12.7 mm heavy machine gun.
- Optionally include a .50-calibre heavy machine gun as a second heavy-weapon choice.

Ammunition:
- Each applicable firearm should support a normal ammunition mode and a visible red tracer mode.
- Tracer visibility and apparent size should vary by game-calibre class; do not make every projectile look identical.
- Tracer rounds are a visual gameplay feature; they are not to be described as incendiary unless a separate incendiary mechanic is explicitly implemented.

Projectile behavior:
- Each weapon/calibre needs its own configurable game values for muzzle speed, drag, gravity response, effective range, damage, penetration and firing cadence.
- Projectiles should leave the muzzle quickly; velocity should decrease gradually over distance rather than appearing slow at launch.
- Long shots should show a visible ballistic arc/drop. The player should be able to adjust aim smoothly using normal first-person look controls; later add a dedicated sight/zeroing or elevation adjustment where appropriate.
- Higher-calibre rounds should have greater game impact on cover and terrain than small-arms rounds.
- Include directional shot cracks / bullet whiz when hostile rounds pass near the player.
- Include impact sounds and occasional ricochet / deflection sounds when a round strikes at a shallow angle.
- Values in the first prototype are **gameplay tuning values**, not a claim of exact real-world firing tables. Refine them by playtesting and keep the data configurable.

## Game modes and networking

- Offline single-player mode against AI.
- Local multiplayer over Wi-Fi hotspot / LAN without requiring internet access or a remote game server.
- Start with a small player-count target (2–8 local players) and validate network authority, synchronization and performance before raising it.
- The single-player and LAN modes should share the same combat, map, weapon and match systems where practical.

## Initial implementation status — 2026-11-07

### Added in this commit
- Godot 4.7.2 project scaffold using the Compatibility renderer.
- A procedural 700 m × 700 m brown-earth plateau greybox with rolling ridges, shallow trench cuts and varied elevation.
- Attacker-side and defender-side cover layouts, including sandbag lines, stone/brick barriers and two separated simple defensive buildings.
- Distant low-poly defender silhouettes to establish scale and sightline.
- First-person controller and starter desktop/mobile input bindings.
- Weapon data for AK-74, M4A1, PKM, RPG-7, SVD, DShK and .50-calibre heavy machine gun.
- Configurable projectile simulation with gravity, drag, range, damage and penetration parameters.
- Optional visible red tracer projectile streaks.
- Dust impact particles, destructible cover integrity, shallow-angle ricochet behavior, and procedurally synthesized placeholder shot/impact audio.
- Basic HUD and an Android export preset.
- GitHub Actions workflow for headless validation and Android APK artifact export.
- A headless scene smoke test.

### Explicitly not yet implemented / not yet verified
- Distant defender silhouettes are placeholders, not the final tactical AI.
- The full attacker/defender behavior tree described above is a next milestone.
- AI suppression sensing, cover selection, fallback movement and coordinated assault are not yet complete.
- Local Wi-Fi / hotspot multiplayer is not yet implemented.
- The project currently uses procedural greybox geometry; final high-quality weapon, soldier, building, sandbag and environment assets remain to be created or sourced with clear licences.
- Audio is synthesized placeholder audio, not recorded firearm or battlefield sound design.
- Android APK export and on-device performance are not confirmed until the GitHub Actions run completes and the APK is tested on an Android phone.

## Quality rules

1. Do not call a placeholder a finished feature.
2. Do not add many small maps; polish the initial wide map first.
3. Keep the distant sightline and terrain readability central to level design.
4. Keep code modular and configuration-driven.
5. Test GDScript parsing and scene startup in headless CI before exporting APK.
6. After each major step, record files changed, tests run, results, and unresolved issues in this context file.
7. Never claim a successful APK build without a successful Actions run and artifact verification.


## CI follow-up — 2026-11-07

- First Android workflow attempt stopped before project validation because the legacy Android SDK package name `tools` is no longer available from the current SDK package repository.
- The workflow was changed to use the preinstalled GitHub-hosted Android SDK and install only current packages (`platform-tools`, Android platform 36 and build-tools 36.0.0). These installation steps succeeded in the next run.
- The second attempt downloaded Godot and the Android export templates successfully, but the Godot executable was mistakenly appended to `GITHUB_PATH` as though it were a directory. The subsequent import step therefore could not find the `godot` command. The workflow is being corrected to persist the exact executable path in `GODOT_BIN` and invoke that executable explicitly.
- Android export-template archive is approximately 1.2 GB. The workflow now extracts only the three Android template files instead of unpacking templates for every platform.
- Android orientation changed to landscape to suit the first-person shooter layout.
- Mobile one-shot HUD controls now send press/release on separate button-down/button-up events so reload and weapon-cycle actions can register as discrete input transitions.
- **Validation status:** no successful Godot import, scene smoke test or Android APK export has been confirmed yet. The next CI run must pass all three before an APK can be offered as a tested build.


## Workflow parser correction — 2026-11-07

- GitHub's server-side workflow validation rejected the revised workflow before creating a runner job. The cause was a malformed YAML scalar in the one-line smoke-test step: its shell command contained an embedded quoted executable path. Converted that step to a YAML block scalar. Earlier zero-job runs were workflow-file validation failures, not Godot compile failures.
- Next expected check: workflow should now register its job; inspect Godot project import, scene smoke test, and Android export separately.


## GDScript smoke-test repair — 2026-11-07

- The first registered Godot run successfully downloaded Godot 4.7.2 and Android export templates and completed the project import step.
- The headless scene smoke test then exposed strict GDScript typing errors in `main_world.gd`: generic `abs` / `lerp` inference and ternary numeric expressions inferred as Variant.
- Corrected these expressions with explicit `float` annotations and float-specific `absf` / `lerpf` calls. The next run must confirm scene instantiation and then the APK export; no APK is confirmed from this failed smoke-test run.


## Android export and projectile script fixes — 2026-11-07

- The next CI attempt confirmed that the Godot import step completed and the map/player/HUD scene smoke test reached runtime, but the log still exposed a dependency parse error in `scripts/weapons/projectile.gd`: inferred Variant type for `distance_factor`. The smoke test was too permissive because it checked scene children without explicitly asserting that every required script was instantiable.
- Android export was blocked by the missing ETC2/ASTC texture-compression import setting required by Godot's Android exporter.
- Corrected the projectile explosion-distance calculations with explicit float types and clamped distance factor.
- Enabled `textures/vram_compression/import_etc2_astc=true` in the project rendering settings for Android compatibility.
- Strengthened `tests/smoke_test.gd` to load every core project script and fail when any script cannot instantiate, before creating the battlefield scene.
- **Validation status at this point:** Android SDK setup, Godot download, export-template installation, and headless project import succeeded. The previous run's scene smoke test returned exit code 0 but its log showed the dependency parse error; therefore it is not treated as a clean validation. Android export failed on ETC2/ASTC configuration. The next CI run must show a clean script smoke test and a successful APK export before a build can be shared.


## First successful cloud build — 2026-11-07

- GitHub Actions run [42402765482](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42402765482) completed with **success**.
- Godot 4.7.2 headless project import succeeded.
- The strengthened script smoke test reported: `SMOKE TEST PASSED: all required scripts compile; main scene, terrain, player and HUD initialized.`
- Android debug APK export and artifact upload both succeeded.
- Uploaded artifact: `TacticalStrike-Android-debug` (artifact ID `13585962872`), available for 14 days from the build date.
- The downloaded APK archive was inspected: it contained one APK; ZIP integrity passed; the APK contained `AndroidManifest.xml` and the ARM64 Godot native library. APK size was approximately 27 MB.
- The APK was **not installed or tested on a physical Android device**. CI success proves script/scene smoke validation and APK export, not touch-control quality, frame rate, actual device compatibility, tactical AI or LAN behavior.
- The export log also showed a non-blocking missing project-icon warning. A project icon is added in the next visual refinement pass.

## Visual refinement and repeatable cloud builds — 2026-11-07

- Added an original vector application icon and configured it in `project.godot`.
- Added a GitHub-renderable top-down map blueprint in `docs/battlefield-layout.svg` and explanatory notes in `docs/BATTLEFIELD_DESIGN.md`.
- Added subtle depth haze to support the requested long sightlines and distant-silhouette effect; day/night toggling changes the haze tint as well as the lighting.
- Added a GitHub Actions cache for the Godot Android export templates so subsequent builds can avoid re-downloading and extracting the large template archive.
- **Validation status:** these visual and workflow refinements are committed, but require their own clean CI run. The already successful earlier APK remains the only build confirmed at this point.


## Depth-haze integration syntax repair — 2026-11-07

- The follow-up build (run 42403142402) confirmed the new SVG app icon was imported and the Android SDK/Godot/template setup steps succeeded.
- The strengthened script smoke test caught a GDScript indentation error introduced while adding depth haze and day/night haze tinting in `scripts/world/main_world.gd`. It correctly failed the job before Android APK export; no artifact was produced by that run.
- Corrected the extra indentation on the environment tonemapping statement and moved the day/night environment block out from under the sun-null check. This keeps haze tint switching independent of the sun node's state.
- The next CI run must confirm all scripts compile, the main scene initializes, and Android export succeeds before the refined APK is shared.


## User-reported Android artifact extraction failure — 2026-11-07

- User reported that the successful fog/refinement build downloaded from GitHub Actions was approximately 27.20 MB, but Android archive extraction stopped with an error and left only a partial APK of around 12 MB.
- Inspected the exact successful Actions artifact from run [42403356849](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42403356849), artifact ID `13586278101`, uploaded from commit `8e353a2b5ef01aaded93af81535834b693e53d92`.
- Downloaded the artifact through the connected GitHub integration and verified its complete ZIP CRC table with `unzip -t`: **PASS**, no corrupt entries. The archive contains exactly one `TacticalStrike-debug.apk` entry, 28,523,024 bytes.
- Extracted that exact entry separately. The APK was identified as an Android package, contains 125 ZIP entries including `AndroidManifest.xml`, `classes.dex`, and `lib/arm64-v8a/libgodot_android.so`; a full APK CRC check also passed with no errors.
- Conclusion: the stored GitHub artifact and the APK inside it are not corrupt. The 12 MB output reported by the user is consistent with an interrupted/partial extraction or a damaged/incomplete local download, but the precise device-side cause cannot be identified without the actual local archive/error screenshot. No evidence indicates that the Godot build itself produced a 12 MB APK.
- Compression analysis: the outer GitHub ZIP is 28,309,482 bytes versus the inner APK at 28,523,024 bytes, a saving of only 213,542 bytes (0.75%). This is expected because APK is itself a ZIP container whose contents are already compressed. A local XZ level-9 test reduced the APK by only about 1.4%, so switching to 7z is not expected to materially speed up download.
- For this conversation, extracted the verified APK from the exact current successful artifact as a standalone file so it can be installed directly without first extracting the GitHub artifact ZIP.
- Hardened the GitHub Actions workflow: after export it must test APK ZIP integrity, verify the Android signature with `apksigner`, confirm the manifest/classes/ARM64 Godot library, and generate a SHA-256 checksum before the artifact is uploaded. The artifact now includes the APK and a small validation/checksum report, with maximum ZIP compression. This workflow change requires a fresh CI run; it is not treated as passed until that run succeeds.


## Verified rebuild after extraction report — 2026-11-07

- Added a mandatory post-export validation step to `.github/workflows/android.yml`.
- New successful run: [42405392723](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42405392723), commit `79333aca0d7247c9350fbab8306319bbf092049b`.
- All required pipeline stages succeeded: Godot project import, full core-script smoke test, Android APK export, APK ZIP/CRC test, `apksigner verify`, Android manifest/classes checks, ARM64 native-library check and artifact upload.
- New artifact: `TacticalStrike-Android-verified`, artifact ID `13587750085`, GitHub Actions run 42405392723.
- Artifact ZIP size: 28,309,886 bytes. Inner APK size: 28,523,024 bytes.
- The exact uploaded artifact was downloaded again and independently checked in the working environment: outer ZIP passed `unzip -t`; the extracted APK passed a complete ZIP/CRC test and was identified as an Android package.
- APK SHA-256: `1d3efd4c492828791bf1d9f355e1d49c60154032af5f212d50c168110106e51f`.
- GitHub Actions produced a matching `TacticalStrike-debug.apk.sha256` sidecar and `apk-validation.txt` report. All checks in the report are PASS.
- A standalone copy of this verified APK was generated for the user in the conversation so installation does not require extracting the GitHub Actions outer ZIP.
- Artifact ZIP compression is set to level 9. The APK itself is a ZIP-based Android package with already-compressed contents, so the outer archive is expected to be only about 0.75% smaller than the APK. Stronger 7z/LZMA compression is not expected to materially improve download size; a local high-compression XZ test improved size by only about 1.4%.
- The prior partial 12 MB file is not the build output. Do not install partial files. The standalone APK and checksum above refer to the independently verified complete APK.
- **Remaining limitation:** CI validates file integrity, signature and target ABI, but no physical Android device installation or in-game performance test has yet been carried out.


## Final re-verification after the user's extraction issue — 2026-11-07

- Rebuilt the same main-branch game code after the README/context update using GitHub Actions run [42405548021](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42405548021), head commit `eb066f6de38bdf9d44158ba5d9bb4913597935d8`.
- Run completed **successfully**. Godot import, script smoke test, APK export, APK integrity/signature/ARM64 validation and upload all passed.
- Verified artifact: `TacticalStrike-Android-verified`, artifact ID `13586967951`, size 28,309,889 bytes.
- Independently downloaded the exact artifact again. The outer ZIP passed `unzip -t`; the extracted APK passed its complete ZIP/CRC test and was identified as an Android APK.
- Final standalone APK SHA-256: `566cc17eab9fdf6ca04d60b8c85fbcf45ce31636a1fb6cdd0ebb27394ac26692`.
- APK size: 28,523,024 bytes. CI validation report confirms archive integrity, signature, manifest, DEX and ARM64 native library: all PASS.
- Added `paths-ignore` for README, PROJECT_CONTEXT and documentation-only pushes so future context bookkeeping does not needlessly rebuild the unchanged Android APK. Manual workflow dispatch and actual code pushes continue to build.


## Current final verified build artifact — 2026-11-07

- Latest successful run after the workflow trigger cleanup: [42405706021](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42405706021), commit `61de784136b37a83ed4e8142bda269657aa50d5b`.
- Result: **success** across Godot import, core-script smoke test, APK export, ZIP integrity, APK signature, Android manifest/classes/ARM64 checks, and artifact upload.
- Artifact ID: `13587581782`; artifact name: `TacticalStrike-Android-verified`; size: 28,309,884 bytes.
- Exact artifact downloaded and independently rechecked: outer ZIP passes CRC/integrity test; extracted APK passes its own full ZIP/CRC test and is identified as an Android package.
- Final APK size: 28,523,024 bytes.
- Final APK SHA-256: `118252b53a0ea561c7c9c908da1d2cc9ac6d985a1928893caaa4a916029dcccc`.
- The standalone copy supplied in the conversation and its `.sha256` sidecar were extracted from this exact final artifact. The small validation report confirms archive integrity, APK signature, AndroidManifest.xml, classes.dex and ARM64 native library all PASS.
- Later documentation-only commits do not trigger another build because the workflow now ignores README, PROJECT_CONTEXT and `docs/**`. Code changes and manual workflow dispatches still trigger a build.


## User playtest feedback and first-person usability repair — 2026-11-07

### User-reported result
- User installed the Android APK and reported that the first screen looked like a largely empty beige plane with a very thin dark horizon, black side bars, clipped status text, and almost no visible controls.
- User could rotate the view but could not move, fire, reload, switch weapons, or access settings. The result did not feel like a playable game.
- This feedback is accepted as a real usability failure; a successful APK export and a headless scene-start test did not prove that the Android touch experience was usable.

### Source review findings
- The Android viewport was fixed at 1280×720 but did not specify an expanding aspect policy. On a wider phone display this can preserve a 16:9 game area and leave unused side regions.
- The battlefield used one flat earth material, a 100×100 terrain grid, only 160 small rock instances, and relatively strong early distance haze. At the player's long-range spawn point this produced very weak visible surface detail and hid the defensive sector too much.
- Weapon definitions and projectile code existed, but there was no first-person weapon mesh attached to the camera. Therefore a weapon name/ammunition count in the HUD did not look or feel like holding a weapon.
- The mobile HUD was only a few fixed-position buttons and had no pause, armory, or settings menus. The previous smoke test checked script/scene initialization, not the presence of a usable first-person weapon model or game UI.
- AI combatants, final quality assets and local multiplayer remain separate incomplete milestones; they must not be described as already complete.

### Repair committed for validation
- Changed the mobile stretch aspect policy to `expand` so the game viewport can fill wider landscape displays without fixed 16:9 side pillars.
- Increased terrain tessellation and height variation; added per-vertex dry-earth color variation, a visible dusty approach track, more ground stones and lighter, more distant haze.
- Added a low-poly first-person weapon-and-arms view model, weapon switching model refresh, recoil movement and a muzzle flash aligned with the visible weapon.
- Rebuilt the HUD with a pause menu, settings panel, weapon armory, night/day toggle, sensitivity controls, and explicit mobile movement/fire/reload/sprint/crouch/jump controls. Screen dragging is restricted to the open look region so movement/action controls do not intentionally rotate the camera.
- Wired HUD selection/settings signals to the player, weapon controller and day/night system.
- Expanded the headless smoke test to require the first-person weapon model and pause/armory/settings controls in addition to the existing world/player/HUD checks.
- **Validation boundary:** these changes are pending the next GitHub Actions run. Even after CI passes, an on-device Android playtest is still required to verify that touch buttons render in the expected positions and register correctly. These changes do not complete tactical AI, final 3D art or LAN multiplayer.


## CI-discovered duplicate terrain function correction — 2026-11-07

- The first CI run for the mobile usability repair, run [42407576305](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42407576305), correctly stopped in the strengthened headless smoke test before APK export.
- Exact error: duplicate declaration of `_build_terrain()` in `scripts/world/main_world.gd`. The code-replacement range had inserted the new vertex-coloured terrain function but accidentally retained the old terrain function farther down in the file.
- Removed the obsolete second implementation while retaining the new higher-detail terrain and approach-track mesh. A source-level check confirms exactly one `_build_terrain()` declaration remains.
- The follow-up commit also retains the HUD signal connection and approach-mesh winding corrections.
- **Build status:** the fix is committed; it is not considered validated until the next complete CI run passes project import, script/scene smoke test, Android export, APK signature/integrity checks and artifact upload.


## Successful CI validation of the usability repair — 2026-11-07

- Corrected the duplicate `_build_terrain()` declaration found by the first repair CI run. The corrected file contains exactly one terrain-builder declaration.
- The new main-branch commit is `41eba7c0e3e0337d1d415a4e8c767b249d297562`.
- GitHub Actions run [42407702148](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42407702148) completed with **success**.
- Passed stages: Godot project import, strengthened headless scene smoke test (including camera weapon view-model and pause/armory/settings UI presence), Android debug APK export, ZIP archive validation, Android APK signature verification, manifest/classes checks, ARM64 Godot native-library check, and artifact upload.
- Verified artifact ID: `13588008097`, artifact name `TacticalStrike-Android-verified`.
- Downloaded the exact artifact and independently checked the outer ZIP and inner APK; both passed full ZIP/CRC tests with no errors.
- APK size: `28,535,312` bytes. SHA-256: `32c0358640d1c6112d3e308ca4a071364829bc04f278fc6a01e296da7f042c75`.
- The artifact validation report records PASS for archive integrity, APK signature, `AndroidManifest.xml`, `classes.dex`, and the ARM64 Godot native library.
- **Important test boundary:** this is a successful source/scene/Android-export validation, not a physical-device playtest. The newly built APK has not yet been installed and interacted with on the user's phone. Touch-button placement, real movement/fire response, visual appearance on the phone, and performance still need the user's next playtest. The terrain and weapon shown are still procedural/low-poly prototype geometry, not final AAA-quality assets. Tactical AI and LAN multiplayer are not implemented.

## Second user device playtest: acceptance failure and reference-led rework — 2026-11-07

### User's actual phone feedback
- The user installed the previously validated usability-repair APK and reported that the terrain looked essentially unchanged, the weapons still looked like crude primitive shapes, the muzzle glow was poor, firearm audio remained synthetic, and walking still did not work.
- The user explicitly rejected that build as failing the intended game design. This supersedes any implication that the earlier CI/UI changes provided a playable or visually acceptable game.
- The issue is now treated as a product-level failure, not a request to make small cosmetic adjustments. A successful APK export did not establish game quality; the previous source/scene checks were insufficient.

### Reference research completed
- Reviewed Special Forces Group 2 mobile control descriptions and gameplay screenshots. Its practical mobile pattern is movement input on the left, look/aim on the right, and separate right-side combat/action controls. Its control layout and sensitivity are customizable. This project uses those interaction principles as a reference only; no proprietary game code, models, textures, sounds or branding are copied. Reference: https://special-forces-group-2.en.uptodown.com/android
- Reviewed Insurgency: Sandstorm and Squad / Kohat terrain screenshots as environmental art references. The target direction is a dry, rocky, rolling plateau with irregular ridgelines, gullies, exposed rock, sparse dry vegetation, tracks and defensible compounds—not a beige plane and not a dune desert. Reference imagery includes the Insurgency Sandstorm Outskirts preview and Squad Kohat outpost: https://steamcommunity.com/games/581320/announcements/detail/1616141061517089867 and https://joinsquad.com/
- Selected Poly Haven's Rocky Gravel CC0 PBR material for the ground: diffuse/albedo, OpenGL normal and roughness maps. It depicts reddish-brown gravel with dense small rocks and dirt. Source: https://polyhaven.com/a/rocky_gravel
- Selected two authored CC0 firearm meshes for the first model-integration milestone: loafbrr_1's AK (Godot-ready archive, 1K textures, approximately 2,670 triangles) and nisu / 3DModelsCC0's M4A1 model. These are real authored weapon meshes rather than hand-assembled box primitives. The AK mesh is a family stand-in, not an exact factory AK-74 mesh. Sources: https://opengameart.org/content/ak and https://opengameart.org/content/m4a1-assault-rifle
- Selected the CC0 Free Firearm Sound Library's recorded AK-47 and AR-15 takes as the closest available recorded audio for the first two weapons, plus CC0 Fantozzi sand footsteps. These are actual recorded firearm samples, but they are not exact AK-74 and M4A1 recordings. The impact/ricochet layer remains a separate synthetic placeholder. Sources: https://opengameart.org/content/the-free-firearm-sound-library and https://opengameart.org/content/fantozzis-footsteps-grasssand-stone
- Licensing was checked on the sources above. The build script pins the downloaded sample recordings to a specific public asset-kit commit and converts them to OGG for the game package. The phone does not need network access while playing.

### Code and build changes prepared on main
- Replaced the old four-button movement D-pad with a true analog virtual joystick on the left. The right half of the screen is reserved for free-look touch-drag; the right-side action cluster has fire, aim, sprint, jump, crouch, reload and next-weapon buttons.
- Reworked the player controller around smooth ground acceleration, limited air acceleration, slope/floor snapping, crouch height, running cadence, small camera bob, touch look, and an aim-down-sights FOV transition. Added actual sand footstep playback from the CC0 footstep samples.
- Replaced the previous primitive cube-based gun assembly with imported external weapon mesh scenes/meshes. The import helper normalizes the mesh dimensions and uses the model manifest to locate the authored AK and M4 assets. The first release's active armory is deliberately restricted to these two imported models rather than displaying fake models for PKM/RPG/SVD/DShK/M2, whose correct models have not yet been integrated.
- Player firing now calls recorded firearm samples from the weapon_audio module, rather than the old generated firing tone. The muzzle effect has been reduced to a brief local light instead of the oversized glowing primitive. Tracer thickness and emissive intensity have also been reduced.
- Increased terrain height variation and ridge/gully amplitudes, increased terrain mesh resolution, added UVs, and applied the Poly Haven Rocky Gravel diffuse/normal/roughness maps. Increased rock-outcrop geometry/count and moved the spawn slightly forward onto the terrain. Reduced atmospheric haze so the middle/far terrain remains visible.
- Added tools/prepare_external_assets.sh to download the CC0 models, PBR maps, and recorded audio during CI, unpack/import them into the project and generate the runtime weapon manifest. Updated GitHub Actions to run this step before Godot import/export.
- Expanded the smoke test to require imported weapon geometry, analog joystick/aim controls and a scripted player movement response; it no longer treats simply creating a HUD as proof that movement is implemented.
- Added/updated docs/EXTERNAL_ASSET_SOURCES.md with source, licence, provenance and asset-specific limitations.

### Explicit limits that remain
- The newly imported AK and M4 meshes are static view models in this pass; production reload, firing, sprint and inspect animation clips, rigged first-person hands and animation blending still need to be implemented and playtested.
- Only AK-74-family and M4A1-family meshes/audio proxies are enabled in this asset milestone. The rest of the planned armory is not yet represented by authentic imported models or exact recorded samples.
- AK-47/AR-15 recordings are close family proxies and must not be described as exact AK-74/M4A1 original recordings. There is no verified exact PKM, RPG-7, SVD, DShK or M2 audio sample in this pass.
- Impacts, ricochets and distant combat atmosphere still need recorded/commissioned sound design. This pass replaces the player's main rifle reports and movement footsteps, not every battlefield sound.
- The external model orientation, scale, placement in the camera and tactile HUD positions still require the user's physical-phone playtest. CI can validate importing a mesh and scripted movement logic; it cannot certify that the gun looks correctly held or that movement feels as smooth as Special Forces Group 2 on the user's device.
- Tactical AI, coordinated attacker/defender behavior and LAN/Wi-Fi multiplayer remain unimplemented.

### Validation state
- All new asset downloads, Godot imports, strengthened movement/model smoke tests and Android exports must pass in the next CI run before an APK can be offered.
- No claim of physical-device validation is made until the user installs and tests this exact new artifact.


## CI correction after external asset integration attempt — 2026-11-07

- The external-asset preparation step succeeded in GitHub Actions and downloaded/unpacked the AK glTF model, M4A1 FBX model, firearm recordings, sand footsteps and all three Rocky Gravel PBR maps.
- The first Godot headless import also completed. The log reported a non-fatal attempt to process the included M4A1 Blender source project without Blender available; the Godot-ready FBX was present. The preparation script now deletes the source .blend files from the staged runtime directory after unpacking, keeping only engine-importable assets.
- The strengthened smoke test did not run to completion because Godot 4.7.2 rejected inferred Boolean types for two touch-look-region variables in player_controller.gd. Both variables are now declared explicitly as bool.
- The run stopped before Android export, so no APK was produced by this attempt. The type fix and Blender-source cleanup are committed for the next full import/smoke/export run.


## External asset integration and analog-movement CI validation passed — 2026-11-07

- Final corrected commit: `6a316880f7776fe4195c08b99f2dfbe6d12f8ab7`.
- GitHub Actions run [42411928830](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42411928830) completed with **success**.
- The external asset download/preparation step passed: both AK and M4A1 source archives, firearm field recordings, Fantozzi sand footfalls and the three Poly Haven Rocky Gravel PBR maps were downloaded and staged. Blender-only .blend source files are excluded from the headless Godot import.
- Godot project import passed. The strengthened smoke test passed, including loading a real imported weapon mesh, creating the analog movement joystick and aim controls, finding the pause/armory/settings UI, and confirming that the player position changes when a movement-vector input is applied.
- Android debug APK export passed. APK archive CRC validation, Android signature verification, AndroidManifest.xml, classes.dex and ARM64 native-library checks all passed.
- Verified GitHub Actions artifact: `TacticalStrike-Android-verified`, artifact ID `13589489249`.
- The exact uploaded artifact was downloaded locally. The outer ZIP passed `unzip -t`; the extracted APK also passed a complete ZIP/CRC test and was identified as an Android package.
- APK size: `47,041,431` bytes. SHA-256: `e9d37e3f2eef27569e59a99a5b1ab66bba4dff2d2cdff8de5d5c6ad6d9309cb3`.
- A standalone copy of the APK, checksum sidecar and validation report were prepared for the user to avoid extracting the outer GitHub artifact ZIP.
- **Important boundary:** CI proves asset download, engine import, scripted movement logic, visible imported mesh instantiation, Android packaging and file/signature integrity. It does not prove that the user sees the rifle at the correct scale/orientation, that the touch joystick feels right on the phone, or that the overall visual quality meets the target. This exact APK has not yet been tested on the user's physical phone.
- **Known content limits:** only AK and M4 have imported firearm meshes in this pass; the AK asset is a close AK-family visual model, not an exact AK-74 factory mesh. The firearm recordings are real AK-47 and AR-15 takes, not exact AK-74/M4A1 takes. First-person arm animations, reload/walk/sprint weapon animation, tactical AI and local multiplayer remain unfinished.


## Screenshot-driven technical corrections and stronger acceptance checks — 2026-11-08

- The user's screenshot shows the previous interface layout mirrored: the HUD's right-anchored top buttons appeared at the left while the status panel appeared at the right. The HUD root is forced to Godot's LTR layout direction to keep the FPS movement and combat controls on fixed left/right sides even when the phone locale is Arabic/RTL.
- The earlier terrain pass incorrectly increased the count and size of dark rock objects. This created a dense, nearly continuous dark silhouette in the distance. Reduced outcrops to 520 small, lighter, low-profile rocks and disabled their cast shadows. The ground PBR maps now provide the main gravel texture detail.
- Replaced the contour-like ridged noise with four broad, broken, irregular ridge chains and rolling shoulders, plus shallow gully cuts. The indexed 256-division terrain mesh now generates normals and tangents; tangent generation is required for the terrain normal map to render correctly.
- The user screenshot showed fire and aim controls too close/overlapping. The new touch layout separates them, keeps the floating movement stick left, puts fire/aim/action controls on the right, and uses a specific touch-index capture for left-thumb joystick movement.
- The actual first-person AK-74M asset includes hands, a skinned rig and named authored idle/draw/walk/run/shot/reload animations. The weapon script checks these clips and connects locomotion to movement state and shot/reload to the authored clips. The active weapon list contains only AK-74M because that is the sole model fully integrated in this milestone.
- The smoke test now validates exact imported animation clip names, left/right control placement, non-overlapping fire/aim hit rectangles, six available recorded firearm takes, a real firing action consuming a magazine round, ammo-mode cycling and player displacement. It also checks that player height does not fall through the terrain collision surface.
- The prior procedural noise audio calls were removed from bullet impact, ricochet and near-miss paths. The user's shot plays a randomized one of six recorded field takes, not a generated legacy tone layered under it. The takes are AK-47 recordings used as the closest available proxy for the AK-74M, not falsely labelled exact AK-74M recordings.
- These refinements are not considered complete until the next Godot import, acceptance smoke test, APK export, archive/signature checks and user phone playtest succeed. No current device-side result is claimed. Bots and multiplayer remain deferred.


## Godot strict-typing correction — 2026-11-08

- The first screenshot-driven rebuild run [42417049347](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42417049347) successfully prepared the licensed AK-74M asset, all six firearm sample files, footsteps and PBR terrain maps. Godot imported the authored glTF scene successfully.
- The expanded headless test then caught strict GDScript inference failures on one mobile-touch Vector2 temporary and three UI Rect2 temporaries, with additional explicit typing added for terrain arrays/tangents and test string/audio arrays.
- Corrected the HUD anchor to an explicit Vector2 and the smoke-test screen/control rectangles to explicit Vector2/Rect2 types. No APK was exported from the failed run. The next CI run must pass the new terrain tangents/material/relief checks, animation clip checks, LTR layout/non-overlap checks, player displacement/floor stability checks, recorded audio resource checks and real fire/ammo state checks before export.


## Terrain winding and collision-root-cause correction — 2026-11-08

- The stricter movement/floor-stability test exposed that the player was falling through the generated terrain even though its scene and collision node existed. This is the actual root cause of the "I can look but cannot walk" failure in the latest candidate.
- Godot uses clockwise triangle winding for front faces. The procedural terrain vertices were previously emitted in the opposite order. Reversed both triangles per terrain cell so the heightfield faces upward as a front-facing surface for Godot's one-sided triangle collision.
- Because reversing the triangle order also reverses the generated geometric normals, the mesh now calls SurfaceTool.generate_normals(true) to keep its lighting normals pointing upward, then generates tangents for the PBR normal map. The terrain material uses normal back-face culling again rather than showing its underside.
- Strengthened the smoke test to inspect the terrain's generated normal array and fail if the surface does not point upward, in addition to verifying height relief, diffuse/normal texture bindings, player movement displacement and vertical floor stability.
- This fix was triggered by a failing test, not by guesswork; the next run must demonstrate the player stays above the terrain collision surface before Android export.


## Terrain winding follow-up — collision accepts both face orientations — 2026-11-08

- In run [42417359337](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42417359337), the project and AK model imported successfully, but the smoke test stopped on its first-vertex normal direction check. It had not reached the player movement/floor stability assertions.
- The mesh now verifies its full normal field by mean upward component and percentage of upward-facing normals rather than rejecting a potentially steep first corner vertex.
- The terrain collision shape is explicitly created as ConcavePolygonShape3D with backface collision enabled. This ensures contact from either side while the triangle winding and normal-map lighting are being validated, so a local winding transition in a gully cannot drop the player's capsule through the surface.
- Terrain material is temporarily rendered two-sided for the same visual diagnosis. The next smoke test explicitly checks that the collision shape has backface collision enabled, then proceeds to player movement and vertical stability.
- This is not declared fixed until that subsequent player movement test passes, followed by APK export and signature/file validation.


## Terrain normal direction measurement — 2026-11-08

- The next CI run [42417621963](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42417621963) confirmed that collision backface support was configured, but the full normal-array test measured mean normal Y = -0.905 with 0 of 66,049 normals pointing upward.
- This gave a decisive measurement: the extra `flip=true` argument was inverting the terrain's generated normals. Removed that flip; the mesh now keeps the current triangle order, generates standard normals, then generates tangents. Two-sided terrain rendering and two-sided concave collision remain enabled while the player floor test validates the collision.
- No APK was exported in this failed run. The next run is expected to re-evaluate normal direction first, then continue to player floor stability and the remaining weapon/UI/ammo checks.


## Replace expensive concave collision with a native terrain heightmap — 2026-11-08

- CI confirmed the terrain's full vertex-normal field was inverted by `generate_normals(true)`; the flip flag was removed and the standard generated normals are used.
- The subsequent headless job remained slow while evaluating the full 256×256 concave trimesh during the movement/floor stability test. The terrain is a heightfield with no caves or overhangs, so a HeightMapShape3D is the correct physics representation and much faster than a general concave triangle soup.
- Replaced the collision mesh with a HeightMapShape3D using 257×257 samples from the exact same _terrain_height(x,z) function and the same visual-grid spacing. The heightmap uses a uniform scale on all axes, with stored heights divided by that spacing to preserve the exact world height.
- The new smoke test explicitly checks HeightMapShape3D size/data and then exercises the actual player's movement and floor-stability assertions. This should test the same hilly surface while avoiding a heavyweight concave physics shape.
- The prior run [42417767291](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42417767291) failed before reaching player movement because the generated terrain normals were inverted (mean Y -0.905). No APK was exported. The new heightmap build remains pending full CI validation.


## Player movement and terrain smoke test passed; Android export guard corrected — 2026-11-08

- The first build using HeightMapShape3D collision, run [42418050146](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42418050146), passed the complete headless scene smoke test. This is the first run to pass the full set of new checks after the screenshot:
  - 257×257 native heightmap collision is present and correctly sized.
  - The terrain has upward-facing generated normals, tangents and bound Rocky Gravel diffuse/normal maps.
  - Battlefield topography relief and the less-dense ground stones pass their checks.
  - The actual imported AK-74M model/rig/animation clips are present.
  - The mobile HUD root uses LTR; the movement stick is on the left; fire is on the right; fire/aim hit targets do not overlap.
  - The scripted joystick input moves the player and the player does not fall through/below the terrain.
  - All six recorded firearm takes are available; firing consumes one magazine round; tracer ammo mode cycles correctly.
- Android export then created and signed the APK successfully, but the workflow step returned failure because its final asset-existence assertions still checked obsolete files from the previous AK/AR asset pass (`ak47_27.ogg`, `ar15_24.ogg`) instead of the new six AK sample names and the new AK-74M model paths. This was a stale CI guard, not a Godot project import or GDScript failure.
- Updated the export step's final required-file checks to require the actual pinned AK-74M glTF/bin/base-colour textures, current AK recording sample paths, sand footsteps and terrain PBR diffuse map. The next run must pass Android export, APK integrity, signature and ARM64 checks before an APK can be provided.
- **Validation boundary:** this headless pass proves the player movement logic and collision interaction in Godot CI, but not the touch feel or visual composition on the user's actual phone. The new APK has not yet been produced by a fully green CI run.


## Strengthen mobile touch-to-game acceptance checks — 2026-11-08

- After the latest green smoke test, expanded it again to exercise the HUD's real touch-handling route instead of setting the player's mobile movement vector directly. The test injects a left-side screen-touch press and upward drag into HUD._input, verifies the emitted vector reaches the player controller, holds it over physics frames, releases the same touch index and verifies the player actually changes world position without falling through.
- The test now emits the FIRE button's button_down/button_up signals and verifies a magazine round is consumed; emits AIM and verifies ADS toggles; emits AMMO and verifies the red tracer ammunition mode; and emits RELOAD and verifies that reloading starts with the authored full-reload animation clip.
- This closes a gap between the earlier logic-only movement test and the actual mobile HUD event wiring. It is not yet a phone hardware test, but it gives CI a direct automated check of the touch-event → HUD → player/weapon-controller path.


## Full acceptance workflow passed — animated AK-74M / terrain / mobile input — 2026-11-08

- Latest project source commit validated by GitHub Actions: `71aa6c6784613e47bfbf15c90e5dd54d3a63784f`.
- GitHub Actions run [42418460738](https://github.com/CybersecurityRahbar/Tactical-Strike-Android/actions/runs/42418460738) completed with **success**; all 15 build/validation/upload stages passed.
- The complete asset-preparation step passed for the Cransh FPS AK-74M glTF, mesh binary, resized arms/rifle material maps, six distinct recorded rifle takes, four sand footsteps and Poly Haven Rocky Gravel PBR maps.
- Godot project import and strengthened smoke test passed. Unlike the earlier test, this pass injects real left-side touch-down/drag/touch-up events into the HUD input handler, verifies the movement vector reaches the player, confirms the player moves over the actual HeightMapShape3D floor without falling below it, and checks the right-hand fire/aim hit targets do not overlap or get mirrored by RTL layout.
- Terrain acceptance checks passed: 257×257 native heightmap collision; 256×256 indexed visual terrain mesh; upward-facing vertex normals and generated tangents; PBR diffuse/normal maps bound to the material; sufficient vertical relief; controlled ground outcrop count.
- Weapon acceptance checks passed: imported skinned AK-74M/arms scene, AnimationPlayer and idle/draw/walk/run/shot/full-reload clips. The test presses FIRE through the button signal and confirms one round is consumed, toggles AIM and TRACER through their HUD buttons, and starts the authored reload animation through the RELOAD button.
- Android debug APK export succeeded. The archive CRC, APK signature, Android manifest, DEX and ARM64 Godot native library validation all passed. Artifact upload completed.
- Verified GitHub Actions artifact: `TacticalStrike-Android-verified`, artifact ID `13592277208`, generated 2026-11-07 22:01 UTC.
- Exact artifact ZIP downloaded locally and independently checked: outer ZIP passed `unzip -t`; inner APK also passed a complete ZIP/CRC check.
- APK size: `43,118,244` bytes. SHA-256: `b4501b67ab7a481dbecfbe76dbe2fb36916693ab21b88a265305a94882b60778`.
- **Critical boundary:** this is a successful CI/source/input-path acceptance build, not a physical-device or visual screenshot sign-off. It verifies the authored model and clip calls exist and that the mobile input event route moves the player in the engine test, but cannot prove the model's final pose/framing, visual mountain quality, touch feel, audio perception or Android performance on the user's particular phone. The user must try this exact APK before the screenshot-level issues are considered resolved.
- Bots, tactical AI and LAN/hotspot multiplayer remain intentionally deferred until the single-player character, weapon, ammunition, audio and battlefield environment are accepted.

## Combat, impact and terrain corrections — 2026-11-09

- Work was performed on `Tactical-Strike-Android2` only; the earlier `Tactical-Strike-Android` repository remains the user's frozen historical copy.
- Reduced and repositioned the first-person weapon view model and applied a root yaw correction based on the user's screenshot showing the rifle presented sideways across the screen. This is an initial transform correction; it still requires visual confirmation on the target phone and may need per-device framing adjustment.
- Changed shot targeting to raycast from the camera center, then direct the physical projectile from a nearby forward launch point toward that aim point. The launch location is still a calibrated camera-relative approximation, not a muzzle marker exported from the model; short-range alignment and cover clearance require device playtesting.
- Removed the automatic every-fifth-round tracer behavior. FMJ/AP no longer unexpectedly render as tracers; the selected TRACER ammunition uses a compact emissive projectile core instead of the former 2.25 m bright box streak that read as a red laser.
- Fixed impact dust configuration: `CPUParticles3D` uses its `mesh` property, not GPU particle `draw_pass_1`. Added a smoke-test assertion for a valid dust mesh.
- Registered `ammo_cycle` in the player input map so the weapon controller does not emit missing-action errors on desktop builds where mobile controls are absent; Y is the desktop binding.
- Reduced terrain startup work by caching the 257×257 height/color samples and reusing height samples for both mesh generation and heightmap collision. Reduced ambient fill from 0.88 to 0.62 to improve terrain shape contrast.
- Local validation on Godot 4.7.2: headless editor import passed; strengthened smoke test passed, including player displacement/floor stability, touch-button firing and reload, FMJ-versus-TRACER selection, and impact dust mesh initialization.
- **Validation still outstanding:** no successful Android export from this change set is recorded yet, and no screenshot/physical-phone playtest confirms the model's new orientation, muzzle alignment, touch feel, visuals, sound mix, or performance. The weapon uses licensed AK-family recordings as documented; exact AK-74M recordings are not claimed. A measured, visually authored muzzle attachment is still preferable to the temporary camera-relative launch point.
- This patch does not create tactical AI, multiplayer, final authored battlefield art, material-specific impact audio or a verified commercial-grade experience. Those remain separate milestones and must not be described as complete.

## Ballistics, audio, impacts and battlefield overhaul — 2026-11-09

Scope: this pass deliberately kept the large 700 m map (long-range engagements were requested) and rebuilt the systems that made the map feel empty and the weapon feel wrong.

### Weapon mount and muzzle

- Root cause of the "backwards rifle": the imported rig's skinned pose runs along **+Z** (rifle mesh spans z = -0.779 .. +1.978, magazine at the negative-Z grip end), while the camera looks down **-Z**. The previous +90° yaw therefore presented the rifle across the screen. The mount is now an authored 180° yaw in `weapon_data.gd`, not a hard-coded rotation in the controller.
- The muzzle marker is placed at the real barrel tip (z = +1.978), computed from the skinned pose of the glTF rather than the unskinned bind-pose AABB (which ends at 0.958 and produced a launch point in the middle of the barrel). `muzzle_direction()` and the smoke test now assert that the barrel axis points down the camera forward axis.
- The first-person rig still uses the previously accepted 0.46 framing scale; the source rig is about 2.76 model units long, so this is a deliberate visual scale, not a metric one.

### Ballistics

- Research sources for the cartridge figures: Wikipedia "5.45×39mm" (7N6 880-900 m/s, G7 BC 0.168, 7T3/7T3M tracer burn distances), Weaponsystems.net 5.45×39 (900 m/s at the muzzle, ~550 m/s at 400 m), Wideners 5.45 vs 7.62 retained-velocity tables. Values were cross-checked and rounded for gameplay.
- New `scripts/weapons/ballistics.gd` holds published cartridge data (5.45×39 7N6 900 m/s, G7 BC 0.168; 7.62×39 715 m/s; 5.56×45 948 m/s; 7.62×54R 830 m/s; 12.7×108 860 m/s) and an exponential velocity-retention curve fitted to published retained velocities (5.45 ≈ 550 m/s at 400 m, 7.62×39 ≈ 486 m/s at 274 m).
- The projectile integrates quadratic drag (`a = -k·v²`) in sub-steps of at most 2 m, plus gravity, so time of flight, drop and impact energy are physically derived: 5.45×39 at 500 m is ≈ 470 m/s, ≈ 3.0 m of drop, ≈ 0.78 s of flight.
- Damage and penetration now scale with the remaining velocity at the impact point instead of being fixed numbers, so a 40 m hit and a 480 m hit differ measurably.
- The rifle is zeroed at 300 m (`zero_distance`): the bore line is lifted by the drop accumulated over that distance, exactly like regulated iron sights. A shot at the sentries (~320 m) now lands on the crosshair instead of ~0.9 m low, while 500 m shots still require real hold-over.
- Ammunition loads are authored per weapon (FMJ / TRACER / AP) with their own velocity, damage and penetration scales; `build_shot_spec()` merges weapon + load + cartridge.
- Tracers are no longer a long bright box or a moving dot: the round now renders a thin additive streak (≤ 2.1 m, aligned with velocity) that ignites after 22 m, plus a real supersonic crack when a round passes within 7 m of the listener.

### Audio

- Root cause of "one tap plays several shots": the upstream AK takes are **multi-shot burst recordings** (the first take is 9.94 s containing about 10 shots at ~620 rpm). The asset step now detects transients, extracts the **last** shot of each take into a ~0.3-0.65 s single report with its real decay, and encodes that. The smoke test rejects any sample longer than 1.2 s.
- Weapon reports use a larger 3D unit size, distance attenuation filtering and random pitch, so repeated fire does not sound identical.
- New `scripts/effects/impact_audio.gd` synthesises and caches impact impulses per surface (dirt, sand, stone, brick, wood, metal, flesh), ricochet whine and supersonic crack, so material-specific impact sound exists without extra downloads.

### Impacts

- `impact_fx.gd` now composes four layers per hit: surface-tinted dust, solid debris/splinters, sparks for stone/brick/metal, and a short-lived smoke puff; amount, speed and lifetime scale with the round's kinetic energy.
- Impacts farther than 170 m from the player skip sparks/smoke to protect mobile fill rate.
- Cover pieces carry a `surface` meta and now burst into debris with sound when destroyed; grazing hits on hard cover ricochet with sparks and a whine.

### Battlefield

- One map, three readable regions: a broad walkable plain in the centre, a ridged rocky massif to the east, and a flat-topped plateau with cliff edges to the west, enclosed by ridges at both ends.
- The four full-width ridge chains that blocked the old 480 m sightline were removed. The plain now has two knee-high rises (≤ 2.6 m) and dry wadis for cover, while the defender line sits on a 9 m knoll so it stays visible from the spawn at ~500 m.
- Terrain is split into two surfaces: textured soil for walkable ground and a triplanar rock material for cliffs and peaks (triplanar avoids stretched UVs on vertical faces). Ground colour is vertex-tinted by altitude.
- Rock scatter is generated from a deformed low-poly mesh in three size classes (boulders on slopes, stones in the basin, scree on massifs), plus dry scrub in the plain.
- Lighting was reworked: warmer low sun with 4-split shadows out to 260 m, a cool sky fill light, procedural sky with a sun disc, height-aware aerial fog, filmic tonemapping, mild contrast/saturation grading and glow for muzzle/tracer highlights.

### Hittable defenders

- The nine decorative capsule silhouettes are now `StaticBody3D` targets with separate body/head hit zones, armour, health, hit flash and flinch, a fall-down death, respawn after 16 s and a HUD message with the hit distance. Three exposed sentries sit at ~320 m so the first engagement is reachable without a long walk.
- There is still **no AI**: defenders do not move or shoot back. This pass makes long-range ballistics observable, not a complete firefight loop.

### Validation and boundaries

- Local verification: Godot 4.7.2 headless editor import passed, and `tests/smoke_test.gd` passed end to end (terrain surfaces, triplanar rock, muzzle alignment, ballistic decay/drop, single-shot audio length, tracer mesh, surface impact FX and audio, target body/head damage, touch movement, firing, ADS, reload).
- Not verified: no Android export from this change set, no screenshot or physical-device playtest. Weapon framing/ADS sight alignment, terrain look, sound mix and frame rate on a real phone still need a device check.
- Not implemented: enemy AI, multiplayer, additional weapon models, magnification/optics, bullet penetration through bodies.
