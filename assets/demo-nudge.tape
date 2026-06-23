Output assets/demo-nudge.gif
Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 700
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 35ms

Hide
Type "source assets/setup-demo-nudge-env.sh"
Enter
Sleep 1s
Type "( sleep 5 && printf 'use prepared statements for all DB queries\n' > .claudeloop/nudge-phase-2.md ) &"
Enter
Sleep 0.5s
Type "clear"
Enter
Sleep 0.3s
Show

Type "claudeloop"
Enter

# Phase 1 (~3s) + Phase 2 attempt 1 (~4s) + BASE_DELAY 3s + Phase 2 retry (~4s) + margin
Sleep 18s
