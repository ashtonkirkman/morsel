# Body scans

The Body tab measures you from three photos so you can watch waist, body fat, lean mass, arms and thighs move
over weeks of dieting or training. It is a port of the owner's FreeFit body scanner (MediaPipe on a Python
server) to Swift, running **entirely on the phone**. Nothing is uploaded to analyse a photo.

> Photo estimates, not a tape measure. Expect **±5–10 %** on circumferences and body fat. The value is in the
> trend: scan the same way each time (same distance, light, clothes, time of day). This is not medical advice.

## The three poses

| Step | Pose | What it is used for |
|---|---|---|
| 1 | Front, arms at sides (required) | Height scale, lengths, waist (narrowest torso row), thigh and calf widths, neck, body fat |
| 2 | Front, arms out (T-pose) | Arm span and ape index, upper-arm / forearm widths, chest and hip widths (arms are clear of the torso) |
| 3 | Left side profile | Torso depth at chest / waist / hips → better circumferences (otherwise typical depth ratios are assumed) |

The capture screen shows a faint silhouette for the pose, a self-timer (3 / 5 / 10 s) so you can prop the phone
up and step back, a front/back camera flip and a library picker. Each photo is analysed immediately and shown
with the detected skeleton and the person mask tinted; retake as often as you like. The front photo is
required, the other two are optional and simply widen what can be measured.

Requirements: full body visible from head to feet, a plain background, even light, fitted clothing. The
detector reports FreeFit's messages ("No pose detected. Ensure your full body is visible and well-lit."), a
"whole body not visible" message when head or ankles are missing, a pose-mismatch warning when the arms do not
match the requested pose, and a "busy background" warning when a large part of the mask lies away from the
body. Warnings do not block saving; the affected numbers are marked low confidence.

## How it works (`FreeTrack/Core/BodyScan`)

1. **Normalise** the photo (`.up` orientation, long edge ≤ 1280 px). Stored copies are JPEGs (≤ 1600 px) in
   `PhotoStore` with a `bodyscan-` prefix.
2. **Pose**: `VNDetectHumanBodyPoseRequest` (Vision) gives 19 joints. They map 1:1 onto the MediaPipe landmarks
   FreeFit used (nose, shoulders, elbows, wrists, hips, knees, ankles); Vision has no heel, see scale below.
3. **Segmentation** (`BodySegmenter` protocol):
   - `VisionPersonSegmenter` — `VNGeneratePersonSegmentationRequest` at `.accurate`. Always available, default.
   - `SAM2Segmenter` — Meta's Segment Anything 2.1 (Apple's Core ML conversion), optional download, see below.
     Positive point prompts sit on shoulder-mid, hip-mid, torso centre, nose, knees, elbows, ankles; negative
     prompts in the four corners. Any model error falls back to Apple Vision silently.
4. **Validation** (`PoseValidator`): full body present, pose geometry matches the step, mask agrees with the
   joints (`maskQuality` 0…1).
5. **Measurement** (`BodyMeasurementEngine`, pure Swift, unit-tested against a synthetic stick figure):
   - **Scale**: pixels per cm from the mask — top of head is the highest foreground row in the columns around
     the nose, the sole is the lowest foreground row under each ankle — accepted when it is 1.05–1.30× the
     nose→ankle distance. Fallback: nose→ankle × 1.13 (FreeFit used nose→heel × 1.08; the ankle sits higher).
   - **Lengths** from joints: upper arm, forearm, arm, thigh, shin, leg, torso, shoulder width, hip joint span,
     arm span (T-pose only), ape index, torso:leg, shoulder:hip.
   - **Widths** from the mask: limbs are scanned perpendicular to the bone at 40–60 % of its length (median of
     five rows). When one side runs into another body part (arm against torso, thigh against thigh) the width
     is twice the clear side. Waist = minimum torso row width between 45–70 % shoulder→hip inside the hip-span
     ±10 % window (as in `analyzer.py`); chest = row at 25 % on the T-pose; hips = widest row 85–110 %; neck =
     narrowest row 60–80 % of the way from nose to shoulders. The side photo gives depth at the same rows.
   - **Circumferences**: limbs ≈ π × width × k with **k = 0.95 for arms, 1.0 for thighs and calves, 0.95 neck**.
     Torso rings use Ramanujan's ellipse perimeter with the front width and the side depth; without a side
     photo depth is assumed to be **0.72 × width (waist), 0.70 (chest), 0.80 (hips)** and the result is capped
     at medium confidence.
   - **Composition**: body fat = Relative Fat Mass, `64 − 20 × height/waist` (men) or `76 − …` (women), clamped
     3–55 %. The US Navy tape formula is shown too when the neck is measurable (women also need hips). Lean mass
     = weight × (1 − body fat); waist:hip and waist:height ratios.
   - **Symmetry**: left/right asymmetry % for arms, legs, thighs and shoulders, averaged across front and T-pose.
   - **Confidence** per metric (low / medium / high) from the joint confidences, mask quality and pose match.
     Photo-based body fat is never above medium.
6. **Comparison** (`BodyScanComparison`, from `comparator.py`): percent change per metric; "significant" =
   more than **2 %** (FreeFit used 3 %) over circumferences, widths and composition, sorted by magnitude.

### Data

`BodyScan` (SwiftData) stores inputs, flattened key metrics (waist, chest, hips, arms, thighs, calves,
shoulder width, body fat, lean mass, arm span, arm/leg lengths), the full `BodyMeasurements` as JSON, the
joints per pose as JSON (so the skeleton overlay can be redrawn without a mask) and the three photo file
names. `BodyScanDTO` carries every scalar plus `measurementsJSON` for the sync layer — **photos and joints
are never synced**. The first scan becomes the baseline; any scan can be made the baseline later.

The weight entered for a scan is written back to the profile and the calorie/macro goals are recalculated
from it, so the dashboard stays in step with the scale.

## Segment Anything 2.1 (optional)

Body tab → gear → "Use Segment Anything". The toggle downloads Apple's official Core ML conversion of Meta's
SAM 2.1 Small from Hugging Face (`apple/coreml-sam2.1-small`, ≈ 94 MB; the Tiny variant is ≈ 80 MB) into
`Application Support/SAM2/small`, compiles the three `.mlpackage`s with `MLModel.compileModel(at:)` and
loads them with `computeUnits = .all`. Installed state is derived from the files on disk, never persisted.

Model interface, as verified from the repository and Apple/Hugging Face's `sam2-studio` sample (details and
`// VERIFY:` notes in `SAM2Model.swift`):

| Model | Inputs | Outputs |
|---|---|---|
| `SAM2_1SmallImageEncoderFLOAT16` | `image` 1024×1024 RGB (squashed, normalisation baked in) | `image_embedding` [1,256,64,64], `feats_s0` [1,32,256,256], `feats_s1` [1,64,128,128] |
| `SAM2_1SmallPromptEncoderFLOAT16` | `points` float32 [1,N,2] in 1024-space, `labels` int32 [1,N] (1 fg, 0 bg), N ≤ 16 | `sparse_embeddings` [1,N+1,256], `dense_embeddings` [1,256,64,64] |
| `SAM2_1SmallMaskDecoderFLOAT16` | `image_embedding`, `sparse_embedding` (2…15 tokens → ≤ 14 points), `dense_embedding`, `feats_s0`, `feats_s1` | `low_res_masks` [1,3,256,256] logits, `scores` [1,3] |

The best-scoring mask is upscaled bilinearly to the photo and thresholded at 0. Downloads can be cancelled,
failures are shown in the settings sheet, and every scan still works with Apple Vision if SAM 2 is missing or
throws. Remove the model from the same sheet.

## Accuracy caveats

- Scale comes from your entered height; a wrong height scales every length and circumference.
- Circumferences are ellipse estimates from one or two silhouettes; loose clothing, hands near the hips or
  a tilted camera inflate them. Keep the phone level at hip height, 2–3 m away.
- RFM / Navy body fat are population formulas (±5–10 % at best) — fine for trends, not for diagnosis.
- Apple Vision's mask is soft around hair, feet and thin limbs; SAM 2 is noticeably tighter. Neither handles
  patterned backgrounds or other people in frame.
- Photos taken with the front camera are un-mirrored before analysis so "left" stays your left.

## Privacy

Analysis is on-device (Vision / Core ML). Photos are stored only in the app's Application Support folder,
excluded from sync, and deleted with the scan. The one-time explainer sheet says exactly this before the
first scan. `NSCameraUsageDescription` mentions body scans. Nothing in this feature talks to a server except
the optional SAM 2 model download from huggingface.co.
