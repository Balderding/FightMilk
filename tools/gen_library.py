"""Generates app/assets/exercises.json - the bundled exercise library (with how-to blurbs).

One line per exercise:  id | name | equipment | primary | secondary | pattern | swap group | joints | compound(1/0) | about
- equipment: barbell dumbbell machine cable smith kettlebell bodyweight band
- muscles/joints: space separated; joints = shoulders lowerBack knees wrists (+ EXTRA_JOINTS below: elbows hips neck ankles upperBack)
- pattern picks the icon pose; swap group = exercises that can replace each other
- about: our own short explanation (what it works, how to do it, one cue)
The icon id is "<pattern>_<equipment>" (drawn by gen_icons.py).
Run: python tools/gen_library.py
"""
import json, pathlib

DATA = r"""
# ---------------- CHEST: flat / decline press ----------------
bench_press|Bench press|barbell|chest|triceps shoulders|press|chest_press|shoulders wrists|1|The classic chest builder. Lie with eyes under the bar, feet planted, shoulder blades pinched. Lower to mid-chest, press up and slightly back. Keep wrists stacked over elbows.
db_bench_press|Dumbbell bench press|dumbbell|chest|triceps shoulders|press|chest_press|shoulders|1|Flat press with a dumbbell in each hand, so each side works on its own and you get a deeper stretch. Lower until elbows are just below the bench, then press up and slightly in.
machine_chest_press|Machine chest press|machine|chest|triceps shoulders|press|chest_press||1|A guided press that lets you push hard without balancing a bar. Set the seat so handles line up with mid-chest, keep your back on the pad and press until arms are nearly straight.
smith_bench_press|Smith bench press|smith|chest|triceps shoulders|press|chest_press|shoulders wrists|1|Bench press on a fixed track. Position the bench so the bar touches mid-chest. Good for pushing near failure without a spotter; use the safety hooks.
push_up|Push-up|bodyweight|chest|triceps shoulders core|pushup|chest_press|wrists|1|Hands a bit wider than shoulders, body in a straight line from head to heels. Lower your chest to the floor and push back up. Make it harder by raising your feet or adding weight.
dips|Dips|bodyweight|chest|triceps shoulders|dip|chest_press|shoulders|1|On parallel bars, lean forward a little and lower until shoulders are just below elbows, then press up. Leaning forward hits chest more; staying upright shifts it to triceps.
decline_bench_press|Decline bench press|barbell|chest|triceps|press|chest_press|wrists|1|Bench press with the head lower than the hips. Shorter range and easy on the shoulders; bring the bar to the lower chest.
decline_db_press|Decline dumbbell press|dumbbell|chest|triceps|press|chest_press||1|Dumbbell press on a decline bench. Lower chest focus with a long, comfortable stretch.
floor_press|Barbell floor press|barbell|chest|triceps|press|chest_press||1|Bench press lying on the floor. Elbows stop on the floor, which cuts the range and spares the shoulders while overloading the lockout.
db_floor_press|Dumbbell floor press|dumbbell|chest|triceps|press|chest_press||1|Dumbbell press from the floor. Pause the elbows lightly on the ground each rep. A good shoulder-friendly option.
kb_floor_press|Kettlebell floor press|kettlebell|chest|triceps|press|chest_press||1|Press a kettlebell from the floor with the bell resting on the back of the forearm. Keep the wrist straight.
cable_chest_press|Cable chest press|cable|chest|triceps|press|chest_press||1|Standing or seated press between two cable stacks. Constant tension all the way through; step forward to load the start.
hammer_chest_press|Plate-loaded chest press|machine|chest|triceps shoulders|press|chest_press||1|Plate-loaded press with independent arms. Load it heavy; press each side evenly and control the way back.
weighted_push_up|Weighted push-up|bodyweight|chest|triceps shoulders core|pushup|chest_press|wrists|1|A push-up with a plate on your back or a weight vest. Log the added weight; keep the hips from sagging.
deficit_push_up|Deficit push-up|bodyweight|chest|triceps shoulders|pushup|chest_press|wrists|1|Push-up with hands on plates or handles so the chest can go below hand level. More stretch for the chest.
band_chest_press|Band chest press|band|chest|triceps|press|chest_press||1|Anchor a band behind you at chest height and press forward. Handy at home or as a finisher. Log reps; use a stronger band to progress.
band_push_up|Band push-up|band|chest|triceps core|pushup|chest_press|wrists|1|Push-up with a band across your back held under each hand. The band gets harder near the top.
# ---------------- CHEST: incline ----------------
incline_bench_press|Incline bench press|barbell|chest|shoulders triceps|incline|incline_press|shoulders wrists|1|Bench set to about 30 degrees to work the upper chest. Lower to the top of the chest, keep shoulder blades pinned, press straight up.
incline_db_press|Incline dumbbell press|dumbbell|chest|shoulders triceps|incline|incline_press|shoulders|1|Upper-chest press with dumbbells on a low incline. Let the elbows sit around 45 degrees from the body; press up and slightly together.
incline_machine_press|Incline machine press|machine|chest|shoulders triceps|incline|incline_press||1|Machine press angled upward for the upper chest. Keep the chest up and the back on the pad.
smith_incline_press|Smith incline press|smith|chest|shoulders triceps|incline|incline_press|shoulders|1|Incline press on a fixed track. Line the bar up with the upper chest; easy to push near failure safely.
cable_incline_press|Low-to-high cable press|cable|chest|shoulders triceps|incline|incline_press||1|Press from low pulleys up and forward for the upper chest with constant tension.
landmine_chest_press|Landmine chest press|barbell|chest|shoulders triceps|incline|incline_press||1|Press one end of a landmine bar up from the chest, kneeling or standing. Shoulder-friendly upper-chest pressing.
reverse_grip_bench|Reverse-grip bench press|barbell|chest|triceps|incline|incline_press|wrists|1|Bench press with palms facing you. Hits the upper chest and triceps; use a spotter and a careful grip.
incline_push_up|Incline push-up|bodyweight|chest|triceps|pushup|incline_press|wrists|1|Push-up with hands on a bench. Easier than the floor; good for high reps or warm-ups.
decline_push_up|Decline push-up|bodyweight|chest|shoulders triceps|pushup|incline_press|wrists|1|Push-up with feet raised on a bench, which shifts work toward the upper chest and shoulders.
# ---------------- CHEST: fly ----------------
pec_deck|Pec deck|machine|chest||fly|chest_fly|shoulders|0|Machine fly. Sit tall, slight bend in the elbows, bring the handles together in a hugging arc and squeeze. Do not let the arms swing too far back.
cable_fly|Cable fly|cable|chest||fly|chest_fly|shoulders|0|Stand between two high pulleys and bring the handles together in front of you. Constant tension; think of hugging a big tree.
db_fly|Dumbbell fly|dumbbell|chest||fly|chest_fly|shoulders|0|Lie flat, arms slightly bent, open wide until you feel a chest stretch, then bring the weights back up in an arc. Go light and controlled.
low_cable_fly|Low-to-high cable fly|cable|chest|shoulders|fly|chest_fly||0|Fly from low pulleys up to face height for the upper chest.
incline_db_fly|Incline dumbbell fly|dumbbell|chest|shoulders|fly|chest_fly|shoulders|0|Fly on an incline bench for the upper chest. Keep the elbows soft and stop at a comfortable stretch.
band_fly|Band fly|band|chest||fly|chest_fly||0|Anchor a band behind you and bring the ends together in front. A light pump exercise for the chest.
svend_press|Plate squeeze press|bodyweight|chest|shoulders|fly|chest_fly||0|Squeeze a plate between your palms at chest height and press it straight out. Constant inner-chest squeeze; log the plate weight.
cable_crossover_low|Cable crossover|cable|chest||fly|chest_fly||0|Pulleys at shoulder height, step forward and cross the hands slightly at the end. Great finisher for a chest day.
# ---------------- SHOULDERS: overhead ----------------
overhead_press|Overhead press|barbell|shoulders|triceps core|overhead|overhead_press|shoulders lowerBack wrists|1|Standing barbell press. Squeeze glutes and brace, press the bar straight up past your face, then push your head through at the top. Do not lean back.
seated_db_press|Seated dumbbell shoulder press|dumbbell|shoulders|triceps|overhead|overhead_press|shoulders|1|Sit with back support, dumbbells at ear height, press up until arms are nearly straight. Keep the ribs down.
machine_shoulder_press|Machine shoulder press|machine|shoulders|triceps|overhead|overhead_press|shoulders|1|Guided overhead press. Set the seat so handles start at shoulder height and press without arching your lower back.
smith_overhead_press|Smith overhead press|smith|shoulders|triceps|overhead|overhead_press|shoulders|1|Standing or seated press on the Smith track; lets you focus on pushing hard.
kb_press|Kettlebell press|kettlebell|shoulders|triceps core|overhead|overhead_press|shoulders|1|Clean a kettlebell to the shoulder and press it overhead, fist up, biceps by the ear. Works shoulders and core stability.
landmine_press|Landmine press|barbell|shoulders|chest triceps|overhead|overhead_press||1|Press the end of a landmine bar up and forward with one arm. Very shoulder-friendly pressing.
smith_shoulder_press_seated|Seated Smith shoulder press|smith|shoulders|triceps|overhead|overhead_press|shoulders|1|Seated press on the Smith machine with back support.
seated_barbell_press|Seated barbell press|barbell|shoulders|triceps|overhead|overhead_press|shoulders wrists|1|Overhead press from a seat with back support. Less lower-back demand than standing.
push_press|Push press|barbell|shoulders|triceps quads|olympic|overhead_press|shoulders lowerBack|1|Dip the knees slightly and drive up to help the bar overhead, then lock it out. Lets you handle more than a strict press.
arnold_press|Arnold press|dumbbell|shoulders|triceps|overhead|overhead_press|shoulders|1|Start palms facing you at chin height, rotate them outward as you press up. Works all three heads of the shoulder.
standing_db_press|Standing dumbbell press|dumbbell|shoulders|triceps core|overhead|overhead_press|shoulders|1|Standing press with dumbbells; brace the core and keep ribs down.
pike_push_up|Pike push-up|bodyweight|shoulders|triceps|pushup|overhead_press|shoulders wrists|1|Hips high in an upside-down V, lower your head toward the floor between your hands. Bodyweight shoulder press.
handstand_push_up|Handstand push-up|bodyweight|shoulders|triceps|overhead|overhead_press|shoulders wrists|1|Kick up to a handstand against a wall and lower your head to the floor, then press back up. Advanced.
band_overhead_press|Band overhead press|band|shoulders|triceps|overhead|overhead_press||1|Stand on a band and press the handles overhead. Light, joint-friendly pressing.
z_press|Z press|barbell|shoulders|triceps core|overhead|overhead_press|shoulders lowerBack|1|Seated on the floor, legs straight, press a barbell overhead. Brutal for core and strict shoulder strength.
# ---------------- SHOULDERS: lateral / front ----------------
db_lateral_raise|Dumbbell lateral raise|dumbbell|shoulders||lateral|lateral_raise||0|Raise dumbbells out to the sides until arms are level with shoulders, leading with the elbows. Light weight, no swinging. Builds wider shoulders.
cable_lateral_raise|Cable lateral raise|cable|shoulders||lateral|lateral_raise||0|One arm at a time from a low pulley across the body. Constant tension on the side delt.
machine_lateral_raise|Machine lateral raise|machine|shoulders||lateral|lateral_raise||0|Pads on the upper arms; raise to shoulder height. Easy to keep strict.
kb_lateral_raise|Kettlebell lateral raise|kettlebell|shoulders||lateral|lateral_raise||0|Lateral raise holding kettlebells by the handle. Same form as dumbbells.
upright_row_cable|Cable upright row|cable|shoulders|traps|lateral|lateral_raise|shoulders wrists|0|Pull a bar or rope up along the body to chest height, elbows high and wide. Stop before shoulders pinch.
lean_away_lateral|Leaning lateral raise|dumbbell|shoulders||lateral|lateral_raise||0|Hold a post and lean away, raise one dumbbell out to the side. Longer range for the side delt.
band_lateral_raise|Band lateral raise|band|shoulders||lateral|lateral_raise||0|Stand on a band and raise the ends out to the sides. Good high-rep pump.
barbell_upright_row|Barbell upright row|barbell|shoulders|traps|lateral|lateral_raise|shoulders wrists|0|Pull a barbell up close to the body to chest height, elbows leading. Use a wider grip to keep it shoulder-friendly.
db_front_raise|Dumbbell front raise|dumbbell|shoulders||frontraise|front_raise||0|Raise dumbbells straight in front to shoulder height. Works the front delt; often already busy from pressing, so keep it light.
cable_front_raise|Cable front raise|cable|shoulders||frontraise|front_raise||0|Front raise from a low pulley between the legs. Smooth tension through the whole lift.
plate_front_raise|Plate front raise|bodyweight|shoulders||frontraise|front_raise||0|Hold a plate at both sides and raise it to eye level. Log the plate weight.
barbell_front_raise|Barbell front raise|barbell|shoulders||frontraise|front_raise||0|Front raise with a light barbell or EZ bar, arms nearly straight.
band_front_raise|Band front raise|band|shoulders||frontraise|front_raise||0|Stand on a band and raise it in front to shoulder height.
# ---------------- SHOULDERS: rear ----------------
reverse_pec_deck|Reverse pec deck|machine|rear_delts|traps|rear|rear_delt||0|Face the pec deck and open the arms back in a wide arc. Works the rear shoulder, which balances all the pressing.
face_pull|Face pull|cable|rear_delts|traps|rear|rear_delt||0|Rope at face height, pull toward your forehead with elbows high and hands apart. Great for shoulder health.
db_rear_delt_fly|Dumbbell rear delt fly|dumbbell|rear_delts|traps|rear|rear_delt|lowerBack|0|Bend forward with a flat back and raise light dumbbells out to the sides. Lead with the elbows.
cable_rear_delt_fly|Cable rear delt fly|cable|rear_delts||rear|rear_delt||0|Cross the cables at shoulder height and pull them apart behind you. Constant tension on the rear delts.
band_pull_apart|Band pull-apart|band|rear_delts|traps|rear|rear_delt||0|Hold a band at shoulder height with straight arms and pull it apart to your chest. Simple, great warm-up.
chest_supported_rear_fly|Chest-supported rear fly|dumbbell|rear_delts|traps|rear|rear_delt||0|Lie chest-down on an incline bench and raise dumbbells out to the sides. Takes the lower back out of it.
# ---------------- BACK: rows ----------------
barbell_row|Barbell row|barbell|back|biceps rear_delts|row|row|lowerBack|1|Hinge forward with a flat back, pull the bar to your lower ribs, squeeze, lower under control. Keep the torso still.
one_arm_db_row|One-arm dumbbell row|dumbbell|back|biceps rear_delts|row|row||1|One hand and knee on a bench, pull the dumbbell toward your hip. Big range, easy on the lower back.
chest_supported_row|Chest-supported row|machine|back|biceps rear_delts|row|row||1|Chest on the pad, pull the handles back and squeeze the shoulder blades. No lower-back strain.
seated_cable_row|Seated cable row|cable|back|biceps rear_delts|row|row||1|Sit tall, pull the handle to your stomach, chest up, then let the shoulders stretch forward. Do not rock.
t_bar_row|T-bar row|barbell|back|biceps rear_delts|row|row|lowerBack|1|Straddle a landmine bar and row the handle to your chest. Heavy upper-back work.
smith_row|Smith row|smith|back|biceps|row|row|lowerBack|1|Bent-over row on the Smith track. Steady path, lets you focus on the squeeze.
chest_supported_db_row|Chest-supported dumbbell row|dumbbell|back|biceps rear_delts|row|row||1|Lie chest-down on an incline bench and row two dumbbells. Strict and back-friendly.
inverted_row|Inverted row|bodyweight|back|biceps|row|row||1|Hang under a bar or Smith bar with straight body, pull your chest up to it. Lower the bar or raise feet to make it harder.
kb_row|Kettlebell row|kettlebell|back|biceps|row|row||1|One-arm row with a kettlebell; same form as the dumbbell row.
cable_row_wide|Wide-grip cable row|cable|back|rear_delts|row|row||1|Seated row with a wide bar, pulling to the upper stomach with elbows out. More upper back and rear delt.
machine_row|Machine row|machine|back|biceps|row|row||1|Seated row machine. Chest on the pad, drive elbows back.
pendlay_row|Pendlay row|barbell|back|biceps rear_delts|row|row|lowerBack|1|Barbell row from the floor each rep with the torso near flat. Explosive pull, reset on the ground.
seal_row|Seal row|barbell|back|biceps rear_delts|row|row||1|Lie face down on a high bench and row the bar up to it. Zero cheating, zero lower-back load.
meadows_row|Meadows row|barbell|back|biceps rear_delts|row|row||1|Stand side-on to a landmine and row the bar end with one hand. Big stretch for the lats.
yates_row|Underhand barbell row|barbell|back|biceps|row|row|lowerBack|1|Barbell row with palms up and a more upright torso, pulling to the stomach. More lats and biceps.
single_arm_cable_row|Single-arm cable row|cable|back|biceps|row|row||1|Seated or standing one-arm row from a cable. Let the shoulder reach forward, then pull to the hip.
band_row|Band row|band|back|biceps|row|row||1|Anchor a band at chest height and row it to your stomach. Good at home or as a warm-up.
iso_lateral_row|Plate-loaded high row|machine|back|biceps rear_delts|row|row||1|Plate-loaded row pulling down and back. Works the upper back and lats hard.
trx_row|Suspension row|bodyweight|back|biceps|row|row||1|Lean back holding suspension straps and pull your chest to the handles. Walk feet forward to make it harder.
# ---------------- BACK: vertical pulls ----------------
lat_pulldown|Lat pulldown|cable|lats|biceps|pulldown|vertical_pull||1|Grip a little wider than shoulders, pull the bar to your upper chest, elbows down and back. Lean back only slightly.
pull_up|Pull-up|bodyweight|lats|biceps|pulldown|vertical_pull|shoulders|1|Hang with palms away, pull until your chin is over the bar, lower all the way. Add weight with a belt when you can do plenty.
chin_up|Chin-up|bodyweight|lats|biceps|pulldown|vertical_pull|wrists|1|Pull-up with palms facing you. More biceps, often easier than a pull-up.
machine_pulldown|Machine pulldown|machine|lats|biceps|pulldown|vertical_pull||1|Lever pulldown machine. Pull the handles down toward your sides and squeeze the lats.
assisted_pull_up|Assisted pull-up machine|machine|lats|biceps|pulldown|vertical_pull||1|Pull-up with a pad pushing you up. Log the assistance as the weight; less assistance means progress.
close_grip_pulldown|Close-grip pulldown|cable|lats|biceps|pulldown|vertical_pull||1|Pulldown with a narrow V-handle to the upper chest. Long range for the lats.
neutral_grip_pull_up|Neutral-grip pull-up|bodyweight|lats|biceps|pulldown|vertical_pull||1|Pull-up on parallel handles, palms facing each other. The most joint-friendly pull-up grip.
single_arm_pulldown|Single-arm cable pulldown|cable|lats|biceps|pulldown|vertical_pull||1|Kneel or sit and pull one handle down to your side. Lets each lat work fully.
band_pulldown|Band pulldown|band|lats|biceps|pulldown|vertical_pull||1|Anchor a band high and pull it down to your chest, elbows to the sides.
band_assisted_pull_up|Band-assisted pull-up|band|lats|biceps|pulldown|vertical_pull|shoulders|1|Pull-up with a band under your knee or foot to help. Use thinner bands as you get stronger.
kneeling_lat_pulldown|Kneeling cable pulldown|cable|lats|biceps|pulldown|vertical_pull||1|Kneel in front of a high cable and pull a bar down to your chest. Simple alternative when the pulldown station is busy.
# ---------------- BACK: lat isolation ----------------
straight_arm_pulldown|Straight-arm pulldown|cable|lats||pullover|lat_iso||0|Arms nearly straight, push the bar or rope from eye level down to your thighs. Feels the lats without the biceps.
db_pullover|Dumbbell pullover|dumbbell|lats|chest|pullover|lat_iso|shoulders|0|Lie across a bench holding one dumbbell over your chest, lower it behind your head, pull it back over. Stretches lats and chest.
machine_pullover|Pullover machine|machine|lats||pullover|lat_iso||0|Machine that lets the lats pull the arms down in an arc. Very direct lat work.
band_straight_arm_pulldown|Band straight-arm pulldown|band|lats||pullover|lat_iso||0|Straight-arm pulldown with a band anchored high.
# ---------------- LEGS: squat ----------------
back_squat|Back squat|barbell|quads|glutes core|squat|squat|knees lowerBack|1|Bar on the upper back, brace hard, sit down between your hips until thighs are at least level, stand up driving through the whole foot. Knees track over toes.
front_squat|Front squat|barbell|quads|glutes core|squat|squat|knees wrists|1|Bar resting on the front of the shoulders, elbows high. Upright torso, very quad-heavy and easier on the back.
leg_press|Leg press|machine|quads|glutes|legpress|squat|knees|1|Feet shoulder-width on the platform, lower until knees are well bent without the lower back lifting, press back up. Big leg work with no balance needed.
hack_squat|Hack squat|machine|quads|glutes|squat|squat|knees|1|Back on the pad, shoulders under the pads, squat deep. Heavy quad work with the back supported.
smith_squat|Smith squat|smith|quads|glutes|squat|squat|knees|1|Squat on the Smith track. Feet slightly in front lets you sit back; good for pushing hard safely.
goblet_squat|Goblet squat|dumbbell|quads|glutes core|squat|squat|knees|1|Hold one dumbbell at your chest and squat between your knees. Teaches a great upright squat.
kb_goblet_squat|Kettlebell goblet squat|kettlebell|quads|glutes core|squat|squat|knees|1|Goblet squat holding a kettlebell by the horns at your chest. Sit down between your knees with an upright torso.
pendulum_squat|Pendulum squat|machine|quads|glutes|squat|squat|knees|1|Swinging-arc squat machine. Deep knee bend, very quad-focused, light on the back.
belt_squat|Belt squat|machine|quads|glutes|squat|squat|knees|1|Load hangs from a hip belt, so legs work hard with no load on the spine.
safety_bar_squat|Safety bar squat|barbell|quads|glutes core|squat|squat|knees|1|Squat with a cambered, padded bar and handles in front. Easier on shoulders and wrists.
box_squat|Box squat|barbell|quads|glutes hamstrings|squat|squat|knees lowerBack|1|Sit back onto a box, pause, then stand. Teaches depth and builds power out of the hole.
pause_squat|Pause squat|barbell|quads|glutes|squat|squat|knees lowerBack|1|Back squat with a 2-second pause at the bottom. Builds strength where most people stall.
zercher_squat|Zercher squat|barbell|quads|glutes core|squat|squat|knees|1|Hold the bar in the crook of the elbows and squat. Very upright, hard on the core.
db_squat|Dumbbell squat|dumbbell|quads|glutes|squat|squat|knees|1|Squat holding a dumbbell in each hand at your sides. Keep the chest up and sit between the hips; a simple way to load squats without a rack.
air_squat|Bodyweight squat|bodyweight|quads|glutes|squat|squat|knees|1|Squat with no weight, arms forward for balance. Warm-up or high-rep finisher.
v_squat|V-squat machine|machine|quads|glutes|squat|squat|knees|1|Plate-loaded squat machine with shoulder pads; quad-friendly and stable.
band_squat|Band squat|band|quads|glutes|squat|squat|knees|1|Stand on a band with it over the shoulders and squat. Gets harder at the top.
leg_press_single|Single-leg leg press|machine|quads|glutes|legpress|squat|knees|1|Leg press with one leg at a time. Evens out left/right differences.
horizontal_leg_press|Seated leg press|machine|quads|glutes|legpress|squat|knees|1|Seated horizontal leg press. Same idea as the sled; keep the lower back on the pad.
# ---------------- LEGS: single leg ----------------
db_split_squat|Dumbbell Bulgarian split squat|dumbbell|quads|glutes|lunge|lunge|knees|1|Back foot on a bench, front foot forward, drop straight down until the back knee nearly touches the floor. Tough but very effective.
walking_lunge|Dumbbell walking lunge|dumbbell|quads|glutes|lunge|lunge|knees|1|Step forward into a lunge, push through the front heel and step into the next one. Keep the torso tall.
smith_split_squat|Smith split squat|smith|quads|glutes|lunge|lunge|knees|1|Split squat on the Smith track for extra balance.
db_step_up|Dumbbell step-up|dumbbell|quads|glutes|lunge|lunge|knees|1|Step onto a box with one foot and stand up fully, without pushing off the back foot. Lower slowly.
reverse_lunge|Barbell reverse lunge|barbell|quads|glutes|lunge|lunge|knees|1|Step back into a lunge and return. Easier on the knees than forward lunges.
kb_lunge|Kettlebell lunge|kettlebell|quads|glutes|lunge|lunge|knees|1|Lunge holding a kettlebell in each hand or at the chest.
db_reverse_lunge|Dumbbell reverse lunge|dumbbell|quads|glutes|lunge|lunge|knees|1|Step back into a lunge holding dumbbells. Knee-friendly single-leg work.
barbell_split_squat|Barbell split squat|barbell|quads|glutes|lunge|lunge|knees|1|Split stance with a bar on your back, drop the back knee toward the floor.
bodyweight_lunge|Bodyweight lunge|bodyweight|quads|glutes|lunge|lunge|knees|1|Lunges with no load. Good warm-up or high-rep burnout.
lateral_lunge|Lateral lunge|dumbbell|quads|glutes adductors|lunge|lunge|knees|1|Step wide to the side and sit into that hip, other leg straight. Works inner thighs too.
curtsy_lunge|Curtsy lunge|dumbbell|glutes|quads|lunge|lunge|knees|1|Step one leg behind and across, like a curtsy. Hits the outer glutes.
pistol_squat|Pistol squat|bodyweight|quads|glutes core|lunge|lunge|knees|1|Squat all the way down on one leg with the other straight in front. Advanced balance and strength.
cable_split_squat|Cable split squat|cable|quads|glutes|lunge|lunge|knees|1|Split squat holding a low cable handle. Smooth constant load.
band_split_squat|Band split squat|band|quads|glutes|lunge|lunge|knees|1|Split squat standing on a band held at the shoulders.
# ---------------- LEGS: hinge ----------------
deadlift|Deadlift|barbell|hamstrings|glutes back|hinge|hinge|lowerBack|1|Bar over mid-foot, grip just outside the legs, chest up and back flat. Push the floor away and stand tall; lower the same way. Brace before every rep.
romanian_deadlift|Romanian deadlift|barbell|hamstrings|glutes|hinge|hinge|lowerBack|1|Start standing, push the hips back with soft knees, slide the bar down the thighs until hamstrings stretch, then drive the hips forward.
db_romanian_deadlift|Dumbbell Romanian deadlift|dumbbell|hamstrings|glutes|hinge|hinge|lowerBack|1|Romanian deadlift with dumbbells in front of the thighs. Hips back, flat back, feel the stretch.
trap_bar_deadlift|Trap bar deadlift|barbell|quads|hamstrings glutes back|hinge|hinge|lowerBack|1|Stand inside a hex bar and lift with a more upright torso. Easier on the back than a straight-bar deadlift.
kb_swing|Kettlebell swing|kettlebell|glutes|hamstrings|hinge|hinge|lowerBack|1|Hike the bell back between the legs, snap the hips forward to float it to chest height. Power from the hips, not the arms.
smith_rdl|Smith Romanian deadlift|smith|hamstrings|glutes|hinge|hinge|lowerBack|1|Romanian deadlift on the Smith machine. A fixed path that helps you focus on the hamstrings.
back_extension|45° back extension|bodyweight|hamstrings|glutes back|hinge|hinge||0|Hips on the pad, lower your chest toward the floor and raise back to a straight line. Hold a plate to load it.
cable_pull_through|Cable pull-through|cable|glutes|hamstrings|hinge|hinge||0|Face away from a low cable with a rope between your legs, hinge back and drive the hips forward. Teaches the hip hinge.
kb_deadlift|Kettlebell deadlift|kettlebell|hamstrings|glutes|hinge|hinge|lowerBack|1|Deadlift a kettlebell from between the feet. A gentle way to learn the movement.
sumo_deadlift|Sumo deadlift|barbell|glutes|hamstrings quads adductors|hinge|hinge|lowerBack|1|Wide stance, hands inside the knees, push the knees out and stand up. Shorter range and more upright.
stiff_leg_deadlift|Stiff-leg deadlift|barbell|hamstrings|glutes back|hinge|hinge|lowerBack|1|Deadlift with nearly straight legs from the floor. Long hamstring stretch; go lighter than a normal deadlift.
good_morning|Good morning|barbell|hamstrings|glutes back|hinge|hinge|lowerBack|1|Bar on the back, push the hips back with soft knees until your torso is near level, then stand. Light and strict.
single_leg_rdl|Single-leg Romanian deadlift|dumbbell|hamstrings|glutes core|hinge|hinge||1|Hinge on one leg with the other reaching back, dumbbell in the opposite hand. Balance and hamstrings in one.
rack_pull|Rack pull|barbell|back|glutes hamstrings traps|hinge|hinge|lowerBack|1|Deadlift from pins at knee height. Overloads the top half and the upper back.
deficit_deadlift|Deficit deadlift|barbell|hamstrings|glutes back quads|hinge|hinge|lowerBack|1|Deadlift standing on a plate so the bar starts lower. Builds speed off the floor.
reverse_hyper|Reverse hyper|machine|glutes|hamstrings back|hinge|hinge||0|Lie face down on the machine and swing the legs up behind you. Strengthens the lower back without loading the spine.
band_good_morning|Band good morning|band|hamstrings|glutes back|hinge|hinge||0|Stand on a band looped behind the neck and hinge forward. Light hinge practice.
glute_ham_raise|Glute-ham raise|bodyweight|hamstrings|glutes|legcurl|ham_curl|knees|0|On a GHD, lower your body forward from the knees and curl yourself back up with the hamstrings. Very hard; use arms to assist at first.
# ---------------- GLUTES ----------------
hip_thrust|Barbell hip thrust|barbell|glutes|hamstrings|thrust|glute||1|Upper back on a bench, bar over the hips, drive the hips up until the body is flat, squeeze hard at the top, chin tucked.
machine_hip_thrust|Machine hip thrust|machine|glutes|hamstrings|thrust|glute||1|Hip thrust machine with a padded belt. Same movement with easier setup.
smith_hip_thrust|Smith hip thrust|smith|glutes|hamstrings|thrust|glute||1|Hip thrust under the Smith bar for a stable path.
db_hip_thrust|Dumbbell hip thrust|dumbbell|glutes|hamstrings|thrust|glute||1|Hip thrust with a dumbbell held across the hips. Upper back on a bench, drive the hips up to a flat line and squeeze the glutes at the top.
glute_bridge|Glute bridge|bodyweight|glutes|hamstrings|thrust|glute||1|Lying on the floor, drive the hips up and squeeze. Add a weight on the hips to progress.
barbell_glute_bridge|Barbell glute bridge|barbell|glutes|hamstrings|thrust|glute||1|Glute bridge from the floor with a barbell over the hips. Shorter range, can go heavy.
single_leg_hip_thrust|Single-leg hip thrust|bodyweight|glutes|hamstrings|thrust|glute||1|Hip thrust on one leg. Hard without any weight.
band_hip_thrust|Band hip thrust|band|glutes|hamstrings|thrust|glute||1|Hip thrust with a band pinned over the hips. Gets hardest at the top.
kb_hip_thrust|Kettlebell hip thrust|kettlebell|glutes|hamstrings|thrust|glute||1|Hip thrust with a kettlebell held on the hips. Good when the barbell is busy; squeeze hard at the top.
glute_kickback|Cable glute kickback|cable|glutes||kickback|glute_iso||0|Ankle strap on a low cable, kick the leg straight back without arching the lower back.
hip_abduction|Hip abduction machine|machine|glutes||abduction|glute_iso||0|Sit and push the pads outward. Works the side glutes that steady your hips.
machine_glute_kickback|Glute kickback machine|machine|glutes||kickback|glute_iso||0|Kickback machine; push the platform back with one leg and squeeze.
band_kickback|Band kickback|band|glutes||kickback|glute_iso||0|Band around the ankles or anchored low, kick one leg back.
cable_hip_abduction|Cable hip abduction|cable|glutes||abduction|glute_iso||0|Stand side-on with an ankle strap and lift the leg out to the side.
band_lateral_walk|Band lateral walk|band|glutes||abduction|glute_iso||0|Band above the knees, half squat, step side to side keeping tension. Great glute warm-up.
frog_pump|Frog pump|bodyweight|glutes||thrust|glute_iso||0|Lie on your back with soles together, knees out, and pump the hips up. High-rep glute burner.
# ---------------- LEGS: isolation ----------------
leg_extension|Leg extension|machine|quads||legext|quad_iso|knees|0|Sit with the pad on your shins and straighten your knees, pause, lower slowly. Pure quad work.
cable_leg_extension|Cable leg extension|cable|quads||legext|quad_iso|knees|0|Ankle strap on a low cable, sit and straighten the knee.
sissy_squat|Sissy squat|bodyweight|quads||legext|quad_iso|knees|0|Lean back and let your knees travel forward as you lower, hips straight. Intense quad stretch.
single_leg_extension|Single-leg extension|machine|quads||legext|quad_iso|knees|0|Leg extension one leg at a time to even out each side.
band_leg_extension|Band leg extension|band|quads||legext|quad_iso|knees|0|Seated, band from behind around the ankle, straighten the knee.
reverse_nordic|Reverse Nordic|bodyweight|quads||legext|quad_iso|knees|0|Kneel upright and lean back slowly with a straight line from knees to head. Strong quad stretch.
lying_leg_curl|Lying leg curl|machine|hamstrings||legcurl|ham_curl||0|Lie face down, pad behind the ankles, curl the heels toward your glutes. Keep the hips down.
seated_leg_curl|Seated leg curl|machine|hamstrings||legcurl|ham_curl||0|Sit with the pad behind the ankles and curl down and back. The stretched hip position makes it very effective.
db_leg_curl|Dumbbell leg curl|dumbbell|hamstrings||legcurl|ham_curl||0|Lie face down with a dumbbell between the feet and curl it up. Go light and slow.
cable_leg_curl|Standing cable leg curl|cable|hamstrings||legcurl|ham_curl||0|Ankle strap on a low cable, curl one heel up behind you.
nordic_curl|Nordic curl|bodyweight|hamstrings||legcurl|ham_curl|knees|0|Kneel with feet anchored and lower your body forward as slowly as you can. Very strong hamstring builder.
standing_leg_curl|Standing leg curl machine|machine|hamstrings||legcurl|ham_curl||0|One leg at a time on a standing curl machine: pad behind the ankle, curl the heel up toward your glute and lower slowly.
band_leg_curl|Band leg curl|band|hamstrings||legcurl|ham_curl||0|Face down, band around the ankle anchored in front, curl the heel up.
slider_leg_curl|Slider leg curl|bodyweight|hamstrings|glutes|legcurl|ham_curl||0|Lie on your back with heels on sliders, hips up, slide the heels in and out.
standing_calf_raise|Standing calf raise|machine|calves||calf|calf||0|Shoulders under the pads, rise onto your toes as high as you can, pause, lower to a full stretch.
seated_calf_raise|Seated calf raise|machine|calves||calf|calf||0|Pad on the knees, lift the heels. Bent knees work the deeper calf muscle.
leg_press_calf_raise|Leg press calf raise|machine|calves||calf|calf||0|Toes on the bottom edge of the leg press platform; push with the ankles only.
smith_calf_raise|Smith calf raise|smith|calves||calf|calf||0|Calf raise under the Smith bar, toes on a plate for extra range.
db_calf_raise|Dumbbell calf raise|dumbbell|calves||calf|calf||0|Hold dumbbells and do calf raises, ideally with toes on a step.
single_leg_calf_raise|Single-leg calf raise|bodyweight|calves||calf|calf||0|Calf raise on one foot from a step. Add a dumbbell when easy.
donkey_calf_raise|Donkey calf raise|machine|calves||calf|calf||0|Bent forward at the hips, rise up on the toes. Great stretch on the calves.
barbell_calf_raise|Barbell calf raise|barbell|calves||calf|calf||0|Calf raise with a barbell on your back, toes on a plate or step. Rise as high as you can, pause, then lower to a full stretch.
tibialis_raise|Tibialis raise|bodyweight|calves||calf|calf||0|Back against a wall, heels out, lift your toes toward your shins. Works the shin muscle and helps knees.
hip_adduction|Hip adduction machine|machine|adductors||adduction|adductor||0|Squeeze the pads together. Works the inner thighs.
copenhagen_plank|Copenhagen plank|bodyweight|adductors|core|adduction|adductor||0|Side plank with the top leg on a bench, bottom leg off the floor. Tough inner-thigh and core hold.
cable_hip_adduction|Cable hip adduction|cable|adductors||adduction|adductor||0|Ankle strap on the inside leg, pull it across the body.
band_adduction|Band adduction|band|adductors||adduction|adductor||0|Band anchored to the side at ankle height; pull the leg inward.
# ---------------- BICEPS ----------------
barbell_curl|Barbell curl|barbell|biceps||curl|biceps|wrists|0|Elbows pinned at your sides, curl the bar up, squeeze, lower slowly. Do not swing the hips.
ez_bar_curl|EZ-bar curl|barbell|biceps||curl|biceps||0|Curl with the angled EZ bar; easier on the wrists than a straight bar.
db_curl|Dumbbell curl|dumbbell|biceps||curl|biceps||0|Curl dumbbells with palms turning up as they rise. Keep the upper arms still.
incline_db_curl|Incline dumbbell curl|dumbbell|biceps||curl|biceps|shoulders|0|Lie back on an incline bench, arms hanging, and curl. The stretch makes the biceps work hard.
hammer_curl|Hammer curl|dumbbell|biceps|forearms|curl|biceps||0|Curl with palms facing each other. Builds the outer arm and forearms.
cable_curl|Cable curl|cable|biceps||curl|biceps||0|Curl a bar from a low pulley. Constant tension top to bottom.
preacher_curl_machine|Machine preacher curl|machine|biceps||curl|biceps||0|Arms on the pad, curl up. The pad stops any cheating.
db_preacher_curl|Dumbbell preacher curl|dumbbell|biceps||curl|biceps||0|One arm on a preacher pad, curl the dumbbell. Strict and hard at the bottom.
kb_curl|Kettlebell curl|kettlebell|biceps||curl|biceps||0|Curl kettlebells by the handle; the offset weight works the grip too.
ez_preacher_curl|EZ-bar preacher curl|barbell|biceps||curl|biceps||0|Preacher curl with an EZ bar. Lower slowly to a near-straight arm.
spider_curl|Spider curl|dumbbell|biceps||curl|biceps||0|Chest down on an incline bench, arms hanging straight down, curl up. Very hard at the top.
concentration_curl|Concentration curl|dumbbell|biceps||curl|biceps||0|Seated, elbow braced on the inner thigh, curl one dumbbell. Great mind-muscle feel.
bayesian_curl|Behind-the-body cable curl|cable|biceps||curl|biceps|shoulders|0|Face away from a low cable, arm slightly behind you, and curl. Loads the biceps in the stretch.
rope_hammer_curl|Rope hammer curl|cable|biceps|forearms|curl|biceps||0|Hammer curl with a rope on a low cable, thumbs up. Keeps tension on the biceps and forearms the whole way; keep elbows at your sides.
reverse_curl|Reverse curl|barbell|forearms|biceps|curl|biceps|wrists|0|Curl with palms facing down. Builds the forearms and the muscle under the biceps.
zottman_curl|Zottman curl|dumbbell|biceps|forearms|curl|biceps||0|Curl palms up, turn palms down at the top, lower slowly. Biceps and forearms together.
drag_curl|Drag curl|barbell|biceps||curl|biceps||0|Drag the bar up the front of your body with elbows moving back. Hits the long head of the biceps.
band_curl|Band curl|band|biceps||curl|biceps||0|Stand on a band and curl. Simple pump work anywhere.
cable_curl_single|Single-arm cable curl|cable|biceps||curl|biceps||0|One-arm curl from a low cable, turning the palm up as you rise.
chin_up_hold|Chin-up negative|bodyweight|biceps|lats|pulldown|biceps||0|Jump to the top of a chin-up and lower as slowly as possible. Builds strength for full chin-ups.
# ---------------- TRICEPS ----------------
triceps_pushdown|Cable triceps pushdown|cable|triceps||pushdown|triceps||0|Elbows tucked at your sides, push the bar down until arms are straight, squeeze, let it up under control.
rope_pushdown|Rope pushdown|cable|triceps||pushdown|triceps||0|Pushdown with a rope, spreading the ends apart at the bottom.
overhead_cable_ext|Overhead cable triceps extension|cable|triceps||overhead_ext|triceps|shoulders|0|Face away from the cable, rope behind your head, straighten your arms overhead. Stretches the long head of the triceps.
db_overhead_ext|Dumbbell overhead triceps extension|dumbbell|triceps||overhead_ext|triceps|shoulders|0|Hold one dumbbell overhead with both hands, lower it behind your head, press back up.
skull_crusher|EZ-bar skull crusher|barbell|triceps||overhead_ext|triceps|wrists|0|Lying on a bench, lower the bar toward your forehead by bending only the elbows, then straighten.
close_grip_bench|Close-grip bench press|barbell|triceps|chest|press|triceps|wrists|1|Bench press with hands about shoulder-width and elbows close. Heavy triceps work.
machine_triceps_ext|Machine triceps extension|machine|triceps||pushdown|triceps||0|Seated triceps machine; push the handles down and straighten the arms.
machine_dip|Machine dip|machine|triceps|chest|dip|triceps||0|Seated dip machine; push the handles down. All the dip, none of the balance.
db_skull_crusher|Dumbbell skull crusher|dumbbell|triceps||overhead_ext|triceps||0|Lying extension with dumbbells, palms facing each other. Easier on the elbows.
bench_dip|Bench dip|bodyweight|triceps|chest|dip|triceps|shoulders wrists|0|Hands on a bench behind you, lower your hips and press back up. Keep the shoulders from rolling forward.
diamond_push_up|Close-grip push-up|bodyweight|triceps|chest|pushup|triceps|wrists|1|Push-up with hands close together under the chest. Bodyweight triceps work.
db_kickback|Dumbbell kickback|dumbbell|triceps||pushdown|triceps||0|Bent over, upper arm level with your body, straighten the elbow to kick the dumbbell back.
cable_kickback|Cable kickback|cable|triceps||pushdown|triceps||0|Kickback with a low cable; tension stays on at the top.
jm_press|JM press|barbell|triceps|chest|press|triceps|wrists|1|A mix of close-grip bench and skull crusher: lower the bar toward your chin, then press. Heavy triceps builder.
single_arm_pushdown|Single-arm pushdown|cable|triceps||pushdown|triceps||0|Pushdown with one handle, palm up or down. Evens out the arms.
band_pushdown|Band pushdown|band|triceps||pushdown|triceps||0|Band anchored high, push down to straight arms.
weighted_dip|Weighted dip|bodyweight|triceps|chest shoulders|dip|triceps|shoulders|1|Dips with a weight on a belt, staying fairly upright for triceps. Log the added weight.
tate_press|Tate press|dumbbell|triceps||overhead_ext|triceps||0|Lying, dumbbells over the chest, bend the elbows out so the bells touch your chest, then press back up.
# ---------------- TRAPS / FOREARMS / NECK ----------------
barbell_shrug|Barbell shrug|barbell|traps||shrug|shrug||0|Hold the bar at arm's length and lift your shoulders straight up toward your ears, pause, lower. No rolling.
db_shrug|Dumbbell shrug|dumbbell|traps||shrug|shrug||0|Hold heavy dumbbells at your sides and lift the shoulders straight up toward the ears. Pause at the top; no rolling the shoulders.
smith_shrug|Smith shrug|smith|traps||shrug|shrug||0|Shrug on the Smith machine; easy to load heavy.
machine_shrug|Machine shrug|machine|traps||shrug|shrug||0|Shrug on a shrug machine or plate-loaded station. Lift the shoulders straight up, hold a second, lower slowly. Easy to load heavy.
cable_shrug|Cable shrug|cable|traps||shrug|shrug||0|Shrug a straight bar from a low cable. The cable keeps tension at the bottom; lift straight up and squeeze the traps.
kb_shrug|Kettlebell shrug|kettlebell|traps||shrug|shrug||0|Shrug holding a kettlebell in each hand. Lift the shoulders straight up and pause; the handles let you grip comfortably.
trap_bar_shrug|Trap bar shrug|barbell|traps||shrug|shrug||0|Shrug inside a hex bar; the neutral grip feels natural.
farmer_carry|Farmer carry|dumbbell|forearms|traps core|carry|carry||0|Pick up heavy dumbbells and walk tall for time or distance. Grip, traps and core. Log seconds as reps.
kb_farmer_carry|Kettlebell farmer carry|kettlebell|forearms|traps core|carry|carry||0|Farmer carry with a heavy kettlebell in each hand. Walk tall with short steps for time or distance. Works grip, traps and core. Log seconds.
trap_bar_carry|Trap bar carry|barbell|forearms|traps core|carry|carry||0|Lift a loaded hex bar and walk. Lets you carry a lot.
suitcase_carry|Suitcase carry|dumbbell|core|forearms|carry|carry||0|Carry one heavy dumbbell on one side and walk without leaning. A sneaky core exercise.
sled_push|Sled push|machine|quads|glutes calves|carry|carry|knees|0|Lean into a sled and drive it forward with short powerful steps. Leg power with no lowering phase. Log seconds; weight = plates on the sled.
dead_hang|Dead hang|bodyweight|forearms|lats|carry|carry|shoulders|0|Hang from a pull-up bar as long as you can. Builds grip and opens the shoulders. Log seconds.
db_wrist_curl|Dumbbell wrist curl|dumbbell|forearms||wristcurl|forearm|wrists|0|Forearms on your thighs, palms up, curl the wrists up and down.
cable_wrist_curl|Cable wrist curl|cable|forearms||wristcurl|forearm|wrists|0|Wrist curls with a bar on a low cable, forearms resting on your thighs. Curl the wrists up and lower all the way for forearm strength.
reverse_wrist_curl|Reverse wrist curl|dumbbell|forearms||wristcurl|forearm|wrists|0|Wrist curl with palms down, for the top of the forearm.
barbell_wrist_curl|Barbell wrist curl|barbell|forearms||wristcurl|forearm|wrists|0|Seated, forearms on the thighs, curl a light barbell with the wrists.
plate_pinch|Plate pinch|bodyweight|forearms||carry|forearm||0|Pinch two smooth plates together and hold for time. Thumb and finger strength. Log seconds.
wrist_roller|Wrist roller|bodyweight|forearms||wristcurl|forearm|wrists|0|Roll a weight up on a rope by twisting a handle, then lower it. Big forearm pump. Log rolls as reps.
band_neck_ext|Neck extension (band)|band|traps||shrug|neck||0|Band around the back of the head, gently nod back against it. Light and controlled.
plate_neck_curl|Plate neck curl|bodyweight|traps||shrug|neck||0|Lie on a bench, plate on the forehead (with a towel), slowly nod up and down. Go very light.
# ---------------- CORE ----------------
cable_crunch|Cable crunch|cable|core||crunch|core||0|Kneel under a high rope, crunch your ribs toward your hips. Move from the spine, not the hips.
machine_crunch|Machine crunch|machine|core||crunch|core||0|Ab crunch machine; curl the chest toward the knees.
hanging_leg_raise|Hanging leg raise|bodyweight|core||legraise|core||0|Hang from a bar and raise your legs, curling the pelvis up. Bent knees make it easier.
captains_chair|Captain's chair knee raise|machine|core||legraise|core||0|Forearms on the pads, back on the pad, raise the knees toward your chest.
plank|Plank|bodyweight|core||plank|core||0|Forearms and toes, straight line from head to heels, squeeze glutes and abs. Log seconds.
ab_wheel|Ab wheel rollout|bodyweight|core||plank|core|lowerBack|0|From the knees, roll the wheel out as far as you can without the lower back sagging, then pull back.
pallof_press|Pallof press|cable|core||rotation|core||0|Side-on to a cable at chest height, press the handle straight out and resist the twist.
db_side_bend|Dumbbell side bend|dumbbell|core||crunch|core||0|Hold a dumbbell on one side and bend sideways, then return. Works the side of the waist.
kb_windmill|Kettlebell windmill|kettlebell|core|shoulders|rotation|core|lowerBack|0|Bell locked overhead, push the hips out and reach down to the opposite foot. Slow and controlled.
woodchop|Cable woodchop|cable|core||rotation|core||0|Pull a cable diagonally across your body from high to low (or low to high), turning through the trunk.
decline_situp|Decline sit-up|bodyweight|core||crunch|core|lowerBack|0|Feet hooked on a decline bench, sit up and lower slowly. Hold a plate to load it.
side_plank|Side plank|bodyweight|core||plank|core||0|On one forearm and the side of your foot, body straight. Log seconds per side.
dead_bug|Dead bug|bodyweight|core||plank|core||0|On your back, arms up and knees bent, lower the opposite arm and leg while keeping the lower back flat.
hollow_hold|Hollow body hold|bodyweight|core||plank|core||0|Lie on your back, arms and legs off the floor, lower back pressed down. Log seconds.
russian_twist|Russian twist|bodyweight|core||rotation|core|lowerBack|0|Sit leaning back with feet up, rotate a weight side to side. Log each side as a rep.
lying_leg_raise|Lying leg raise|bodyweight|core||legraise|core|lowerBack|0|On your back, raise straight legs up and lower slowly without the lower back arching.
reverse_crunch|Reverse crunch|bodyweight|core||legraise|core||0|On your back, curl the knees and hips up off the floor toward your chest.
crunch|Crunch|bodyweight|core||crunch|core||0|Lie on your back and curl your ribs toward your hips. Small, controlled movement.
weighted_plank|Weighted plank|bodyweight|core||plank|core||0|Plank with a plate on your back. Log the plate as weight and seconds as reps.
bird_dog|Bird dog|bodyweight|core|glutes|plank|core||0|On hands and knees, reach one arm and the opposite leg out long, hold, switch. Back-friendly core work.
landmine_rotation|Landmine rotation|barbell|core|shoulders|rotation|core||0|Hold the end of a landmine bar overhead and rotate it side to side in an arc.
cable_side_bend|Cable side bend|cable|core||crunch|core||0|Stand side-on to a low cable holding the handle and bend away from it, then return. Works the side of the waist (obliques).
band_pallof_press|Band Pallof press|band|core||rotation|core||0|Pallof press with a band anchored to the side.
toes_to_bar|Toes to bar|bodyweight|core|lats|legraise|core||0|Hang and lift your toes to touch the bar. Advanced, needs control.
dragon_flag|Dragon flag|bodyweight|core||legraise|core|lowerBack|0|Lying on a bench, hold behind your head and lower your straight body from the shoulders. Very advanced.
stir_the_pot|Stir the pot|bodyweight|core||plank|core||0|Forearm plank on a stability ball, draw small circles. Brutal for the abs.
suitcase_deadlift|Suitcase deadlift|dumbbell|core|glutes|hinge|core||0|Deadlift one dumbbell at your side without leaning. Core anti-bend strength.
farmer_march|Kettlebell march|kettlebell|core|forearms|carry|carry||0|Hold kettlebells and march in place, lifting knees high. Core and grip; log seconds.
# ---------------- POWER / OLYMPIC ----------------
power_clean|Power clean|barbell|glutes|hamstrings traps quads|olympic|power|lowerBack wrists|1|Pull the bar from the floor, jump it up with the hips and catch it on the shoulders in a quarter squat. Technical; learn it with light weight first.
hang_clean|Hang clean|barbell|glutes|hamstrings traps|olympic|power|lowerBack wrists|1|Start with the bar at mid-thigh, dip and explode up, catch on the shoulders.
hang_power_snatch|Hang power snatch|barbell|glutes|shoulders traps hamstrings|olympic|power|shoulders lowerBack wrists|1|Wide grip from mid-thigh, explode up and punch the bar overhead in one move.
clean_and_jerk|Clean and jerk|barbell|glutes|shoulders quads traps|olympic|power|shoulders lowerBack wrists|1|Clean the bar to the shoulders, then drive it overhead with the legs. Full-body power.
thruster|Thruster|barbell|quads|shoulders glutes|olympic|power|knees shoulders|1|Front squat and drive straight into an overhead press in one move. Huge conditioning lift.
db_thruster|Dumbbell thruster|dumbbell|quads|shoulders glutes|olympic|power|knees shoulders|1|Thruster with dumbbells at the shoulders.
db_snatch|Dumbbell snatch|dumbbell|glutes|shoulders hamstrings|olympic|power|shoulders lowerBack|1|One dumbbell from between the feet straight overhead in one explosive pull.
kb_clean|Kettlebell clean|kettlebell|glutes|hamstrings forearms|olympic|power||1|Swing the bell back and pull it into the rack position at the shoulder, wrist straight.
kb_snatch|Kettlebell snatch|kettlebell|glutes|shoulders hamstrings|olympic|power|shoulders|1|Swing the bell and punch it straight overhead in one move. Great conditioning.
high_pull|Barbell high pull|barbell|traps|shoulders glutes|olympic|power|shoulders|1|Explode from mid-thigh and pull the bar to chest height, elbows high.
box_jump|Box jump|bodyweight|quads|glutes calves|olympic|power|knees|1|Jump onto a box landing softly, step down. Leg power; log jumps as reps.
med_ball_slam|Medicine ball slam|bodyweight|core|shoulders lats|olympic|power||1|Lift a slam ball overhead and throw it down hard. Log ball weight and reps.
kb_goblet_clean|Kettlebell swing to goblet squat|kettlebell|glutes|quads|olympic|power|knees|1|Swing the bell up, catch it at the chest and squat. Flowing full-body work.
"""

ISO_RANGE = (10, 15)
TIMED = {"plank", "carry"}
STEP = {"barbell": "barbell", "smith": "barbell", "dumbbell": "dumbbell", "kettlebell": "dumbbell",
        "machine": "machine", "cable": "cable", "bodyweight": "bodyweight", "band": "bodyweight"}
TIMED_IDS = {"plank", "side_plank", "hollow_hold", "weighted_plank", "copenhagen_plank", "dead_hang", "plate_pinch",
             "farmer_carry", "kb_farmer_carry", "trap_bar_carry", "suitcase_carry", "sled_push", "farmer_march"}

# joints added in batch 15 (F236), kept apart so the lines above stay readable
EXTRA_JOINTS = {
    "elbows": "skull_crusher db_skull_crusher jm_press tate_press close_grip_bench overhead_cable_ext db_overhead_ext bench_dip weighted_dip dips machine_dip "
              "diamond_push_up barbell_curl ez_bar_curl preacher_curl_machine db_preacher_curl ez_preacher_curl spider_curl chin_up clean_and_jerk power_clean hang_clean",
    "hips": "back_squat front_squat zercher_squat box_squat pause_squat pistol_squat sumo_deadlift deadlift deficit_deadlift good_morning lateral_lunge curtsy_lunge "
            "copenhagen_plank hip_adduction cable_hip_adduction hanging_leg_raise toes_to_bar lying_leg_raise decline_situp",
    "neck": "band_neck_ext plate_neck_curl handstand_push_up pike_push_up crunch decline_situp barbell_shrug trap_bar_shrug back_squat box_squat pause_squat "
            "good_morning barbell_split_squat barbell_calf_raise",
    "ankles": "box_jump pistol_squat walking_lunge lateral_lunge curtsy_lunge single_leg_calf_raise donkey_calf_raise standing_calf_raise sled_push sissy_squat "
              "tibialis_raise front_squat",
    "upperBack": "barbell_row pendlay_row t_bar_row yates_row deadlift rack_pull deficit_deadlift good_morning front_squat zercher_squat power_clean hang_clean high_pull "
                 "barbell_shrug trap_bar_shrug farmer_carry trap_bar_carry",
}

# how the body lies (P1-10): careful mode while pregnant leaves out lying on the back or front
POSITION = {
    "supine": "bench_press db_bench_press smith_bench_press decline_bench_press decline_db_press floor_press db_floor_press kb_floor_press "
              "close_grip_bench jm_press tate_press reverse_grip_bench skull_crusher db_skull_crusher db_fly db_pullover glute_bridge "
              "barbell_glute_bridge frog_pump dead_bug lying_leg_raise crunch reverse_crunch hollow_hold decline_situp dragon_flag weighted_push_up",
    "prone": "lying_leg_curl seal_row chest_supported_row chest_supported_db_row chest_supported_rear_fly reverse_hyper back_extension",
}

rows = []
for line in DATA.strip().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    f = line.split("|")
    assert len(f) == 10, line
    i, n, eq, pri, sec, pat, swap, joints, comp, about = f
    comp = comp == "1"
    lo, hi = (6, 10) if comp else ISO_RANGE
    if pat == "olympic":
        lo, hi = (3, 5)
    if i in TIMED_IDS:
        lo, hi = (30, 60)
    rows.append(dict(id=i, name=n, equipment=eq, primary=pri.split(), secondary=sec.split(), pattern=pat, swap=swap,
                     joints=joints.split() + [j for j, ids in EXTRA_JOINTS.items() if i in ids.split()], repLow=lo, repHigh=hi, step=STEP[eq],
                     bodyweight=eq in ("bodyweight", "band"), compound=comp, timed=i in TIMED_IDS,
                     icon=f"{pat}_{eq}", about=about.strip()))
    pos = [k for k, ids in POSITION.items() if i in ids.split()]
    if pos:
        rows[-1]["position"] = pos[0]

ids = [r["id"] for r in rows]
for j, l in [*EXTRA_JOINTS.items(), *POSITION.items()]:
    unknown = set(l.split()) - set(ids)
    assert not unknown, (j, unknown)
dupes = {x for x in ids if ids.count(x) > 1}
assert not dupes, dupes
out = pathlib.Path(__file__).resolve().parent.parent / "app" / "assets" / "exercises.json"
out.write_text(json.dumps({"version": 2, "exercises": rows}, indent=1))
print(len(rows), "exercises,", len({r["icon"] for r in rows}), "icons ->", out)
