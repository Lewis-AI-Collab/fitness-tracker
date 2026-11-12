# Fitness log app — product + technical spec (working title "Rep", v0.2)

Personal, phone-only training log you talk to. Built the Shelf way: Flutter (3.47) for iOS + Android, local SQLite (`sqflite`), on-device speech, no accounts, no cloud, sideload APK / Xcode install. No in-app AI. Deeper questions go to Grok via the share sheet, same as Shelf's Export / Share.

## Goals / non-goals
**Goals:** log sets by voice with no typing; plan the week and see strain warnings; 30-second daily check-in; warnings that learn from Lewis's own history and say why; copy or share a workout, day, week, or month as plain text for any AI; a deterministic weekly balance check; goals that change the overload suggestions and flag runs.
**Non-goals:** no LLM/API calls or keys, no wearables/HealthKit in MVP, no social, no coaching programmes, no calorie tracking, no commercial polish or store listing.

## UI rules (apply everywhere)
No explanatory/help text on screens. Icon-only controls, labels on long-press (tooltip on hover). Choices open as pop-ups/pop-outs, never rows of pills. White canvas, one accent colour, British English. Layout uses large titles, rounded cards, and the existing palette only.

## User flows
1. **Log after sets:** tap and hold the mic in the top bar. Say "bench press, 4 sets of 8 at 70 kilos". A confirm card pops up (exercise · 4×8 · 70 kg). It auto-saves after 3 s, or tap any field to fix it (pop-out picker). Logged sets are compact cards: reps × kg, tap a number for a picker, +/− change the set count. Finish opens a bottom sheet with an RPE slider. A routine is a named list of exercises with sets, reps and kilograms, saved on the phone. Start workout opens that routine, or an empty session: tick each set, edit the actual reps and kilograms, and finish or discard. The rest timer is on that screen only. It is labelled, counts from 90 s unless changed, and starts when a set is ticked. Voice note on that screen stores a recording against the session and the current exercise. The same voice flow works for "Muay Thai, 90 minutes, hard" and "ran 5k in 28 minutes, RPE 6".
2. **Plan the week:** Plan tab, 7 day columns. The week opens with load as a percent of target (dotted target and overreach lines) and a period pop-out (day, week, 3 months, year). Balance is four bars — push, pull, legs, core — and the neglected regions use the accent. Lift goals sit on a card with a ruler. Step-up suggestions are arrow chips. Tap a day → pop-up: session type (+ optional muscle groups/intensity), or say it ("Tuesday Thai hard, Wednesday legs heavy"). Strain icons appear on flagged days; tap one for the evidence pop-out.
3. **Daily check-in:** a notification at a set time (default 8am). One screen, six sliders 1–10, or answer by voice in one sentence ("sore 6, energy 4, slept 7 hours…"). Done in about 30 s.
4. **Export:** one share icon. It opens swipeable Workout, Day, Week, and Month cards. Copy puts the plain text on the clipboard. Grok shares that text. Share attaches `fitness.txt`, `fitness-summary-v1.json`, and `summary.md` as well.

## Screens
Today (mic in the bar, Start workout, saved routines, today's plan, set cards, finish sheet, one share icon) · an active workout (current exercise, set ticks, labelled rest timer, voice notes) · Plan (load hero, period pop-out, balance bars, goal ruler, arrow chips, week grid, warnings) · History (calendar, tap day → sessions + check-in) · Insights (learned patterns table, each with N and effect) · Settings (exercise dictionary/aliases, check-in time, goals, import).

## Data model (SQLite)
- `exercises` — id, name, category (strength/cardio/combat/mobility), muscle_groups (list), aliases (list), default_load_factor
- `sessions` — id, date, start_time, type (gym/muay_thai/run/hike/yoga/other), duration_min, rpe (1–10, nullable), notes, raw_transcript
- `sets` — id, session_id, exercise_id, set_count, reps, weight_kg, distance_km, duration_s, rpe
- `plan_items` — id, date, type, muscle_groups, intensity (easy/moderate/hard), duration_min_est
- `checkins` — date, soreness, energy, sleep_quality, sleep_hours, mood, ate_well, stress (1–10), raw_transcript
- `patterns` — key (e.g. `muay_thai:hard>gym:legs_heavy`), n, mean_next_readiness, mean_next_fatigue, last_updated
- `warnings_log` — date, rule, shown, evidence_json (to check later whether warnings were right)
- `goals` — id, kind (`pace`, `lift`, `general`), general (`strength`, `fitness`, `hypertrophy`), exercise_id, target_kg, distance_km, target_pace_s (seconds per km), created_on. Schema version 4. A v1 or v2 file gains goals on open. A v3 file gains routines and voice notes. A newer file is refused.
- `routines`, `routine_exercises`, `routine_sets` — a saved workout: name, ordered exercises, and per exercise the ordered sets with reps and kilograms.
- `voice_notes` — id, session_id, exercise_id, exercise_name, transcript, audio_path, created_at. A note recorded in an active workout, kept with the finished session.

## Load + readiness model (plain terms, no AI)
**Session load** = duration (min) × RPE (session-RPE, the standard sports-science measure). Strength sessions with no duration: estimate 3 min per set. If RPE is missing, use a per-type default (Thai 7, heavy gym 7, run 6, hike 4, yoga 2), replaced by his own average RPE for that type once N ≥ 5.
**Muscle-group load** = sum of sets per group over the last 72 h.
**Readiness (from check-in)** = mean of energy, sleep, mood, ate_well, (11 − soreness), (11 − stress), scaled to 0–100. Fatigue = soreness and energy kept separately as well.
**Weekly load** = sum of session loads over 7 days. **Acute:chronic ratio** = this week ÷ average of the last 4 weeks.

**Rules (defaults, day 1):**
- Two hard days (RPE ≥ 7 or load above his 75th percentile) back to back.
- Same muscle group trained heavy within 48 h.
- Heavy legs then running/Thai the next day.
- Planned weekly load > 1.3 × the 4-week average (shown once ≥ 3 weeks of data).
- Today's check-in readiness < 40 with a hard session planned.

**Personal learning:** after each check-in, the previous day's pattern is recorded. That covers the session-type pair (day −2 → day −1) and the last session alone, and the pattern's next-day readiness/fatigue means are updated. Once a pattern has **N ≥ 3** samples, its mean replaces the default rule for that pattern:
- mean next-day fatigue ≥ 7 (or readiness < 45) → **warning upgraded**, even if the default rule didn't fire;
- mean next-day fatigue ≤ 4 (readiness ≥ 65) → **warning downgraded** to a muted icon;
- in between → keep the default.
Use a rolling window of the last 8 occurrences so it tracks changes in fitness. It works from day 1 on defaults and becomes personal around week 4.
**Evidence text** in the pop-out: "Last 3 times: Thai hard → legs heavy. Next-day fatigue 8, 7, 9." It shows the dates, and tapping a date opens that day.

## Overload rule

For each lift, per week. Working sets are the sets at the heaviest weight; bodyweight work is skipped. The rep range is 8–12 unless that lift already has a stored range. The step is +2.5 kg for an upper-body lift and +5 kg for a lower-body lift. Round the final suggested weight to the nearest 2.5 kg, and round an exact tie down (61.25 + 5 = 66.25 → 65, not 67.5). A low-readiness or strain flag takes precedence over a step-up.

- All reps hit at the top of the range: step up.
- All reps hit with RIR ≥ 2 on every set: step up, even below the top of the range. RIR outside 0–5 does not count.
- Missed reps alone: keep the weight and aim for the reps.
- Low readiness (mean &lt; 40) or a strain warning on the lift's muscles, with the reps hit: hold.
- Missed reps and (low readiness or a strain warning): deload 10%, rounded to 2.5 kg.
- Low readiness and a strain warning, with the reps hit: hold, not deload.
- RIR 0 before the target reps: hold, unless the deload condition applies. RIR 0 after the reps were hit does not hold.

This rule is the default when no general goal is active. A general goal sets the rep range stored for next week, and the load step, while it is the newest general goal. Whether this week hit, missed, or earned an RIR step is still judged on the lift's stored range, or on 8–12 when none is stored. The card aims at the low end of next week's range when reps were missed, and at the high end when they landed inside the previous range. Rounding, deload, and the readiness/strain precedence stay as written above. See Goals.

## Plain-text export

A workout, a day, a week, or a month becomes one plain-text block for pasting into any AI. Copy writes that block to the clipboard. Share opens the system share sheet (`share_plus`) with the same text, so another app can take it. On iOS the sheet is anchored with `sharePositionOrigin`. The JSON and markdown files still ride along.

The block, in order, omitting a heading when it has nothing to say:

1. `# Fitness Tracker` and a scope line: `Workout · Mon 5 Oct`, `Day · Mon 5 Oct`, `Week · 5–11 Oct 2026`, or `Month · …`.
2. One `##` heading per session: `date`, the start time when it was stored, the type, `N min` when a duration was stored, and the session RPE. Sessions are ordered by date, then time, then id.
3. Each lift: `Name · sets x reps x kg`, then `· RIR n` when RIR was logged. Bodyweight is `Name · sets x reps · bodyweight`. A set RPE is added only when that set stored one. A set with no distance, no reps, no weight, and no bodyweight mark is left out.
4. Each run: `Name · km · m:ss · m:ss/km`. Time comes from the set's duration, or from the session duration when the set has none. Pace is duration ÷ distance, rounded to the nearest second, written as minutes:seconds per km.
5. A run that misses a pace goal gets the next line `slow: 5:36/km at 5 km, goal 5:00/km`.
6. Muay Thai blocks: `Pads · 20 min · RPE 8`. Session notes: `Notes: …` on one line.
7. `## Check-ins`, morning before evening. Fields stay in this order and empty ones are left out: soreness, energy, sleep, hours, mood, stress, feel, ate. `2026-10-05 · Morning · soreness 4 · energy 7 · sleep 8 · hours 7.5 · mood 6 · stress 3`. `2026-10-05 · Evening · energy 5 · stress 3 · feel 6 · ate 8`.
8. Week and month only: `## Balance` (below) and `## Next week` (one lift card per line).
9. `## Goals` whenever any goal exists (below).

A workout export is that one session plus the check-ins on its date. A day export is every session that date. Neither includes balance or the next-week cards.

## Balance

Rule-based and deterministic. Lifting sets only: a set with a rep count or a weight, and no distance. Runs are ignored. `full` is ignored. Each set is counted in full for every muscle on the exercise, so a squat's legs, quads, and glutes each receive the same set count. Volume in kg is sets × reps × kg. A missing weight or a missing rep count contributes 0 kg and still counts the sets.

The exercise-to-muscle map is the `muscle_groups` list on the exercise. Splits compare the busiest muscle on each side, not the sum of the side, so those three squat tags are not added together. Ties go to the earlier name in the list.

| Split | One side, in tie-break order | Other side, in tie-break order |
|---|---|---|
| upper / lower | chest, back, shoulders, biceps, triceps, traps, forearms | legs, quads, hamstrings, glutes, calves |
| push / pull | chest, shoulders, triceps | back, biceps, traps |
| front / back chain | chest, quads, shoulders, biceps, core | back, hamstrings, glutes, traps, calves, triceps |

A split is flagged only when both of these hold:

- the heavier muscle has at least **6** sets;
- the lighter muscle has at most **60%** of the heavier muscle's sets (`light × 100 <= heavy × 60`).

Equal counts are not a flag. The percentage printed in the sentence is the nearest integer, and a half rounds away from zero (1 of 6 is 17%). A side with no sets uses the name `legs`, `chest`, `pull`, `push`, `front`, or `back`.

Wording, with no capital and no full stop: `upper-heavy: legs got 30% of the sets chest got`.

The plan screen shows the sets, the volume, and any flags for the week on screen. A week export has one balance block for that range. A month export has one block per Monday–Sunday week that contains lifting sets inside the month. Days outside the month are not included, so a week that crosses the month boundary is clipped to the month. The next week starts on the calendar date seven days later (`DateTime(year, month, day + 7)`), and the week ends six calendar days later, so a clock change cannot move Monday onto Sunday evening and leave that Monday out.

## Goals

One or more goals, each of one kind. Schema version 3, table `goals`.

| Kind | Stored fields | What it does |
|---|---|---|
| `pace` | distance in km, target pace in seconds per km | Flags a run. Does not change the overload step. |
| `lift` | exercise id, target kg | Shows current best against the target. Does not change the overload step. |
| `general` | `strength`, `fitness`, or `hypertrophy` | The newest general goal sets next week's rep range and the step. This week's hit or miss still uses the stored range. |

With no general goal, suggestions stay on the default overload rule (8–12, or that lift's stored range, +2.5 kg upper / +5 kg lower).

| General goal | Reps | Upper step | Lower step |
|---|---|---|---|
| strength | 3–6 | +5 kg | +10 kg |
| fitness | 8–12 | +2.5 kg | +5 kg |
| hypertrophy | 6–12 | +2.5 kg | +5 kg |

Lower body is still legs, quads, hamstrings, glutes, or calves. The final weight is still rounded to the nearest 2.5 kg, and an exact tie still rounds down (61.25 + 10 = 71.25 → 70). Deload stays 10%. A low-readiness or strain flag still outranks a step-up.

A run is flagged when its distance is within **0.05 km** of a pace goal and its pace is strictly slower than the target. Pace is the set duration, or the session duration when the set has none, divided by the distance, rounded to the nearest second. A 10 km run is not judged against a 5 km goal. The on-screen mark is a speed icon; the long-press label is the `slow:` line. An equal or faster pace is not flagged.

Progress lines, on the weekly cards and in every export that includes the goal:

- General: `Strength · 3/23 sets in 3-6`. The count is every lifting set with a rep count in that week or export. Warm-up sets are included. The range is that goal's range.
- Lift: `Bench press · 70 / 100 kg`, the heaviest weight in the range against the target. No weight yet is `- / 100 kg`.
- Pace: `5 km · 5:36/km · goal 5:00/km · slow`, using the fastest matching run. `met` when that pace is at or under the goal. No matching run omits the pace and the mark.

Several general goals can be stored. Suggestions follow the one with the highest id. Each of them still gets its own progress line.

## Voice parser (deterministic)
On-device STT: iOS `SFSpeechRecognizer` (`requiresOnDeviceRecognition`), Android `SpeechRecognizer` (offline preferred), via the `speech_to_text` plugin Shelf already uses, en-GB. Pipeline:
1. Normalise: lowercase, number words → digits ("eight" → 8, "seventy" → 70), strip filler (reuse Shelf's cleanup), and map units "kilos/kg/k" → kg, "lbs/pounds" → lb→kg, "k/km" after a run → km.
2. Split into multiple entries on "then", "and then", ";".
3. Exercise match: longest alias match in the dictionary, then fuzzy fallback (Levenshtein ≤ 2 / phonetic) for mishearings like "bench rest" → bench press. If nothing matches, the card shows "?" and the picker opens.
4. Slot regexes: `(\d+) sets? of (\d+)`, `(\d+) ?x ?(\d+)`, `at (\d+(\.\d+)?) ?(kg|lb)`, `(\d+) (minutes|mins|hours?)`, `(\d+(\.\d+)?) ?(k|km|miles)`, `rpe (\d+)` / intensity words (easy=3, moderate=5, hard=7, brutal=9).
5. Context: if no exercise is said, use the last-logged exercise ("another 2 sets of 8").

| Said | Parsed |
|---|---|
| "bench press, 4 sets of 8 at 70 kilos" | Bench press · 4×8 · 70 kg |
| "squats 5 by 5 100k" | Back squat · 5×5 · 100 kg |
| "Muay Thai, hour and a half, hard" | Muay Thai · 90 min · RPE 7 |
| "ran 5k in 28 minutes, RPE 6" | Run · 5 km · 28 min · RPE 6 |
| "yoga 30 minutes easy" | Yoga · 30 min · RPE 3 |
| "pull-ups 3 sets of 10 bodyweight then rows 3 by 12 at 50" | Two entries |

The seeded dictionary has about 80 exercises plus aliases. Each correction made on the confirm card adds an alias automatically, so the parser learns his phrasing deterministically.

## Grok hand-off
One share icon opens swipeable Workout, Day, Week, and Month cards. Copy and the Grok action use the plain-text block above, which is what gets pasted into Grok or any other AI. Share also attaches `fitness.txt`, `fitness-summary-v1.json` (sessions, sets, check-ins, plan vs actual, warnings, patterns, lift cards, balance, goals, goal progress), and `summary.md`. No keys, no API. On iOS the sheet sets `sharePositionOrigin`. An optional BYO-key "Ask AI" is left for later.

## Privacy
Everything is local: SQLite + app sandbox, speech on-device, no network calls in MVP, no analytics. The only export is one Lewis starts through the share sheet. Backup is a manual JSON export/import.

## MVP vs later
**MVP:** voice logging + confirm card, exercise dictionary, non-gym sessions, Today/Plan/History, check-in (sliders + voice), default rules, pattern learning with evidence, week/month export, iOS + Android sideload.
**v0.2:** plain-text export of a workout, day, week, or month, with copy, Grok, and share from one swipeable deck; weekly balance flags drawn as push/pull/legs/core bars; goals (pace, lift, strength / fitness / hypertrophy) that shape the overload suggestions and flag runs. Schema version 3. The load hero is this period as a percent of the mean of up to four earlier periods with load; overreach is 1.3 × that target.
**Later:** Insights screen polish, widget/lock-screen mic, Apple Health/Health Connect (sleep, HR), Watch quick-log, progression charts / PRs, BYO-key Ask AI, warning-accuracy review ("were the warnings right?").

## Open questions
1. Name: keep "Rep" or something else?
2. Check-in time and reminder: a fixed morning notification, or open-the-app only?
3. Should Muay Thai be split into sub-types (pads/sparring/clinch/conditioning), since they load very differently?
4. Units: kg only, and km or miles for running?
5. Separate repo `Lewis-AI-Collab/<name>`, public like Shelf, or private?
