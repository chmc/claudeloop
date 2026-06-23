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
Type "clear"
Enter
Sleep 0.3s
Show

Type "claudeloop"
Enter

# Phase 1 runs and completes (~3s)
Sleep 5s

# Phase 2 starts and gets stuck (~4s of wrong output)
Sleep 5s

# User nudges the stuck phase
Type "n"
Sleep 0.5s
Enter

# Nudge prompt appears — type guidance
Sleep 1.5s
Type "use prepared statements for all DB queries"
Enter

# Phase 2 retries with nudge and succeeds (~4s)
Sleep 7s
