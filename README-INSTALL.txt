JarBox Gboard Keyboard v3
=========================

This package integrates the custom Gboard-style keyboard into JarBox/J2ME.

FILES
-----
J2MEEmulator/Keyboard/
  JBClipboardManager.h/.m
  JBKeyboardIME.h/.m
  JBKeyboardManager.h/.m
  JBKeyboardView.h/.m
  JarBoxKeyboardIntegration.h

J2MEEmulator/UI/
  J2MEQWERTYKeyboardView.swift

GameViewController.keyboard.patch
  Exact patch for the existing GameViewController.swift. It changes the
  keyboard from an overlay into a layout participant so the emulator viewport
  resizes above it.

INSTALL
-------
1. Replace the existing J2MEQWERTYKeyboardView.swift with the one in this ZIP.
2. Keep the Keyboard files under J2MEEmulator/Keyboard/.
3. Apply GameViewController.keyboard.patch to the current
   J2MEEmulator/UI/GameViewController.swift.

The keyboard manager is now per J2MEQWERTYKeyboardView instance rather than a
singleton, preventing text callbacks from crossing between JAR sessions.

IMPORTANT
---------
Do not add a second copy of any Keyboard/*.h/.m file.
The project uses the J2MEEmulator synchronized group, so the files should be
inside J2MEEmulator/Keyboard/.
